import Foundation
import SwiftData
import Testing
@testable import WagLock

@MainActor
@Suite(.serialized)
struct LibraryMountCoordinatorTests {
    private typealias Coordinator = LibraryMountCoordinator

    private func container() throws -> ModelContainer {
        let schema = Schema([MediaItem.self, SecretNote.self, VaultAlbum.self])
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
    }

    @Test func initializationAndUnauthorizedRequestsNeverOpenAStore() async {
        var calls = 0
        let coordinator = Coordinator { _ in
            calls += 1
            return try container()
        }
        #expect(calls == 0)
        await coordinator.mount(.init(sessionID: UUID(), scope: .legacyOwner)) { false }
        #expect(calls == 0)
        #expect(coordinator.active == nil)
        #expect(!coordinator.isLoading)
        #expect(!coordinator.failed)
    }

    @Test func realGuestFactoryCreatesOnlyAnEphemeralEmptySchema() async throws {
        let coordinator = Coordinator()
        let request = Coordinator.Request(sessionID: UUID(), scope: .ephemeralGuest)
        await coordinator.mount(request) { true }
        let store = try coordinator.container(for: request)
        #expect(store.configurations.allSatisfy { $0.isStoredInMemoryOnly })
        let context = ModelContext(store)
        #expect(try context.fetchCount(FetchDescriptor<MediaItem>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<SecretNote>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<VaultAlbum>()) == 0)
    }

    @Test func reloginAndDomainChangesRequireFreshMountsAndRejectOldRequests() async throws {
        var scopes: [Coordinator.Scope] = []
        let coordinator = Coordinator { scope in
            scopes.append(scope)
            return try container()
        }
        let owner = Coordinator.Request(sessionID: UUID(), scope: .legacyOwner)
        await coordinator.mount(owner) { true }
        let original = try #require(coordinator.active)
        await coordinator.mount(owner) { true }
        #expect(coordinator.active?.id == original.id)
        #expect(scopes.count == 1)
        coordinator.invalidate()
        #expect(throws: Coordinator.Failure.self) { try coordinator.container(for: owner) }
        let relogin = Coordinator.Request(sessionID: UUID(), scope: .legacyOwner)
        await coordinator.mount(relogin) { true }
        #expect(coordinator.active?.id != original.id)
        #expect(throws: Coordinator.Failure.self) { try coordinator.container(for: owner) }
        let guest = Coordinator.Request(sessionID: UUID(), scope: .ephemeralGuest)
        await coordinator.mount(guest) { true }
        #expect(scopes == [.legacyOwner, .legacyOwner, .ephemeralGuest])
        #expect(throws: Coordinator.Failure.self) { try coordinator.container(for: relogin) }
        #expect(try coordinator.container(for: guest) === coordinator.active?.container)
    }

    @Test func lateOwnerOpenCannotReplaceTheNewGuestMount() async throws {
        let gate = Gate()
        let ownerContainer = try container()
        let coordinator = Coordinator { scope in
            if scope == .legacyOwner { return try await gate.wait() }
            return try container()
        }
        let owner = Coordinator.Request(sessionID: UUID(), scope: .legacyOwner)
        let opening = Task { await coordinator.mount(owner) { true } }
        try await gate.requireStarted()
        let guest = Coordinator.Request(sessionID: UUID(), scope: .ephemeralGuest)
        await coordinator.mount(guest) { true }
        let guestMount = try #require(coordinator.active)
        gate.resume(returning: ownerContainer)
        await opening.value
        #expect(coordinator.active?.id == guestMount.id)
        #expect(coordinator.active?.request == guest)
        #expect(!coordinator.failed)
        #expect(throws: Coordinator.Failure.self) { try coordinator.container(for: owner) }
    }

    @Test func lateOwnerFailureCannotEraseTheNewSession() async throws {
        let gate = Gate()
        let coordinator = Coordinator { scope in
            if scope == .legacyOwner { return try await gate.wait() }
            return try container()
        }
        let owner = Coordinator.Request(sessionID: UUID(), scope: .legacyOwner)
        let opening = Task { await coordinator.mount(owner) { true } }
        try await gate.requireStarted()
        let guest = Coordinator.Request(sessionID: UUID(), scope: .ephemeralGuest)
        await coordinator.mount(guest) { true }
        gate.fail()
        await opening.value
        #expect(coordinator.active?.request == guest)
        #expect(!coordinator.failed)
        #expect(!coordinator.isLoading)
    }

    @Test func logoutAuthorizationChangeAndCancellationRejectPendingResults() async throws {
        for reason in 0..<3 {
            let gate = Gate()
            let coordinator = Coordinator { _ in try await gate.wait() }
            var authorized = true
            let request = Coordinator.Request(sessionID: UUID(), scope: .legacyOwner)
            let opening = Task { await coordinator.mount(request) { authorized } }
            try await gate.requireStarted()
            switch reason {
            case 0: coordinator.invalidate()
            case 1: authorized = false
            default: opening.cancel()
            }
            gate.resume(returning: try container())
            await opening.value
            #expect(coordinator.active == nil)
            #expect(!coordinator.isLoading)
            #expect(!coordinator.failed)
        }
    }

    @Test func failedOpenDoesNotFallbackAndRetryPreservesExistingRows() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let schema = Schema([MediaItem.self, SecretNote.self, VaultAlbum.self])
        let configuration = ModelConfiguration(schema: schema, url: root.appendingPathComponent("fixture.store"))
        let fixture = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(fixture)
        context.insert(SecretNote(title: "Retain this fixture", content: "unmodified notes"))
        try context.save()
        let state = RetryState()
        let coordinator = Coordinator { scope in
            #expect(scope == .legacyOwner)
            state.calls += 1
            if state.failing { throw TestFailure.open }
            return try ModelContainer(for: schema, configurations: [configuration])
        }
        let request = Coordinator.Request(sessionID: UUID(), scope: .legacyOwner)
        await coordinator.mount(request) { true }
        #expect(coordinator.active == nil)
        #expect(coordinator.failed)
        #expect(state.calls == 1)
        state.failing = false
        await coordinator.mount(request) { true }
        let reopened = ModelContext(try coordinator.container(for: request))
        let notes = try reopened.fetch(FetchDescriptor<SecretNote>())
        #expect(notes.count == 1)
        #expect(notes.first?.content == "unmodified notes")
        #expect(!coordinator.failed)
        #expect(state.calls == 2)
    }

    @MainActor
    private final class RetryState { var failing = true; var calls = 0 }

    private enum TestFailure: Error { case open }

    @MainActor
    private final class Gate {
        private var continuation: CheckedContinuation<ModelContainer, Error>?
        func wait() async throws -> ModelContainer {
            try await withCheckedThrowingContinuation { continuation = $0 }
        }
        func requireStarted() async throws {
            for _ in 0..<1_000 {
                if continuation != nil { return }
                await Task.yield()
            }
            try #require(continuation != nil)
        }
        func resume(returning container: ModelContainer) {
            continuation?.resume(returning: container)
            continuation = nil
        }
        func fail() {
            continuation?.resume(throwing: TestFailure.open)
            continuation = nil
        }
    }
}
