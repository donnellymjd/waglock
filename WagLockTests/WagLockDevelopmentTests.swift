import Foundation
import SwiftData
import Testing

@testable import WagLock

@MainActor
struct WagLockDevelopmentTests {
    @Test
    func localImportsRemainAvailableBeyondLegacyLimitWithoutPurchase() throws {
        let container = try ModelContainer(
            for: MediaItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        for index in 0..<80 {
            context.insert(MediaItem(
                fileName: "sample-\(index)", fileExtension: ".jpg", fileSize: 1,
                type: .photo, encryptedPath: "fixture-\(index).encrypted"
            ))
        }
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<MediaItem>()) == 80)

        let gallery = GalleryViewModel()
        gallery.modelContext = context
        gallery.showImport()
        #expect(gallery.showImportView)
    }

    @Test
    func separateCredentialNamespacesDoNotReadOrModifyEachOther() throws {
        let fixtureID = UUID().uuidString
        let existingApp = KeychainService(service: "vaultito-test-existing-" + fixtureID)
        let fork = KeychainService(service: "vaultito-test-fork-" + fixtureID)
        defer {
            existingApp.clearAllKeychainData()
            fork.clearAllKeychainData()
        }

        try existingApp.savePassword("existing-fixture-password")
        #expect(!fork.isPasswordSet())
        #expect(!fork.verifyPassword("existing-fixture-password"))
        try fork.savePassword("fork-fixture-password")
        try fork.changePassword(
            oldPassword: "fork-fixture-password", newPassword: "updated-fork-password"
        )
        #expect(existingApp.verifyPassword("existing-fixture-password"))
        #expect(!existingApp.verifyPassword("updated-fork-password"))
        #expect(try fork.retrieveDataPassword(using: "updated-fork-password") == "fork-fixture-password")
    }

    @Test
    func credentialsFollowTheInstalledForkIdentity() {
        #expect(AppConstants.bundleIdentifier == Bundle.main.bundleIdentifier)
        #expect(AppConstants.bundleIdentifier != "com.zeronetspace.unlimited-imports")
        #expect(AppConstants.bundleIdentifier != "com.wq.ZeroNet-Space")
    }
}
