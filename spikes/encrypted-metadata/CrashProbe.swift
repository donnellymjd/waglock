import Foundation
import Darwin

@main
struct MetadataCrashProbe {
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        let root = URL(fileURLWithPath: args[2]).standardizedFileURL.resolvingSymlinksInPath()
        let domain = EncryptedMetadataStore.Domain(libraryID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!, vaultID: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!)
        let key = Data(repeating: 0x4d, count: 32) // Public synthetic probe key only.
        let id = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        if args[1] == "create" {
            let store = try EncryptedMetadataStore.create(at: root, domain: domain, key: key)
            try store.apply(store.access(), revision: 0, mutations: [.put(.init(kind: "note", id: id, payload: Data("original-public-fixture".utf8)))])
        } else if args[1] == "before" || args[1] == "after" {
            let store = try EncryptedMetadataStore.open(at: root, domain: domain, key: key)
            try store.apply(store.access(), revision: 1, mutations: [.put(.init(kind: "note", id: id, payload: Data("changed-public-fixture".utf8)))]) { stage in
                if args[1] == "before", case .beforeCommit = stage { _exit(71) }
                if args[1] == "after", case .afterCommit = stage { _exit(72) }
            }
        } else {
            let store = try EncryptedMetadataStore.open(at: root, domain: domain, key: key)
            try store.verifyAll(store.access())
            let page = try store.page(store.access(), offset: 0, limit: 32)
            let result: [String: Any] = ["fixtureOnly": true, "revision": page.state.revision, "count": page.state.count,
                "payload": String(decoding: page.records[0].payload, as: UTF8.self)]
            print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
        }
    }
}
