import Foundation
import XCTest
@testable import WagLock

@MainActor
final class VaultSessionContextTests: XCTestCase {
    func testDocumentsStayWithinImmutableStorageAndRevocationIsIndependent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let firstStorage = FileStorageService(directory: root.appendingPathComponent("first"), availableCapacity: { _ in Int64.max })
        let secondStorage = FileStorageService(directory: root.appendingPathComponent("second"), availableCapacity: { _ in Int64.max })
        let firstPassword = "PUBLIC first random-like secret"
        let secondPassword = "PUBLIC second random-like secret"
        let firstPath = try firstStorage.saveEncrypted(data: EncryptionService.shared.encrypt(data: Data("first document".utf8), password: firstPassword))
        let secondPath = try secondStorage.saveEncrypted(data: EncryptionService.shared.encrypt(data: Data("second document".utf8), password: secondPassword))
        let first = try VaultSessionContext(vaultID: UUID(), sessionID: UUID(), dataPassword: firstPassword,
            storage: firstStorage, temporaryRoot: root, keychainNamespace: "PUBLIC-context-test")
        let second = try VaultSessionContext(vaultID: UUID(), sessionID: UUID(), dataPassword: secondPassword,
            storage: secondStorage, temporaryRoot: root, keychainNamespace: "PUBLIC-context-test")
        defer { first.revoke(); second.revoke() }
        let firstPreview = first.makeDocumentPreview(), secondPreview = second.makeDocumentPreview()
        await firstPreview.load(path: firstPath, password: firstPassword, fileExtension: "txt", sessionID: first.sessionID)?.value
        await secondPreview.load(path: secondPath, password: secondPassword, fileExtension: "txt", sessionID: second.sessionID)?.value
        XCTAssertEqual(firstPreview.data, Data("first document".utf8))
        XCTAssertEqual(secondPreview.data, Data("second document".utf8))
        await firstPreview.load(path: secondPath, password: secondPassword, fileExtension: "txt", sessionID: first.sessionID)?.value
        XCTAssertNil(firstPreview.data)
        XCTAssertNotNil(firstPreview.error)
        first.revoke()
        XCTAssertFalse(first.isActive)
        XCTAssertTrue(second.isActive)
        XCTAssertNil(firstPreview.data)
        XCTAssertNil(firstPreview.error)
        XCTAssertNil(firstPreview.load(path: firstPath, password: firstPassword, fileExtension: "txt", sessionID: first.sessionID))
        XCTAssertEqual(secondPreview.data, Data("second document".utf8))
        let latePreview = first.makeDocumentPreview()
        XCTAssertNil(latePreview.load(path: firstPath, password: firstPassword, fileExtension: "txt", sessionID: first.sessionID))
        second.revoke()
        XCTAssertNil(secondPreview.data)
    }
}
