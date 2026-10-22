import CryptoKit
import CryptomatorCryptoLib
import Foundation

/// Research only: generates public synthetic data; never opens an app library or Keychain.
@main
struct PortableExportFixture {
    static let outerPassword = "WagLock outer disposable fixture"
    static let innerPassword = "WagLock inner disposable fixture"
    static let manifestName = "waglock-manifest.json"
    enum Failure: Error { case usage, destinationExists, invalidPath, duplicatePath }

    static func json(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted])
    }
    static func hash(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    static func base64url(_ bytes: Data) -> String {
        bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    final class Builder {
        let root: URL
        let cryptor: Cryptor
        private var directoryIDs = ["": Data()]
        private var files: [[String: Any]] = []
        private var names = Set<String>()
        private(set) var encryptedPaths: [String: String] = [:]

        init(root: URL, password: String) throws {
            self.root = root
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            let key = try Masterkey.createNew()
            let wrapped = try MasterkeyFile.lock(masterkey: key, vaultVersion: 999, passphrase: password)
            try wrapped.write(to: root.appendingPathComponent("masterkey.cryptomator"))
            let header = try json(["kid": "masterkeyfile:masterkey.cryptomator", "typ": "JWT", "alg": "HS256"])
            let payload = try json(["format": 8, "shorteningThreshold": 220, "jti": UUID().uuidString, "cipherCombo": "SIV_GCM"])
            let input = base64url(header) + "." + base64url(payload)
            var raw = key.rawKey
            defer { for i in raw.indices { raw[i] = 0 } }
            let signature = HMAC<SHA256>.authenticationCode(for: Data(input.utf8), using: SymmetricKey(data: raw))
            try Data((input + "." + base64url(Data(signature))).utf8).write(to: root.appendingPathComponent("vault.cryptomator"))
            cryptor = Cryptor(masterkey: key, scheme: .sivGcm)
            try FileManager.default.createDirectory(at: directory(Data()), withIntermediateDirectories: true)
        }
        func directory(_ id: Data) throws -> URL {
            let name = try cryptor.encryptDirId(id)
            return root.appendingPathComponent("d/" + name.prefix(2) + "/" + name.dropFirst(2))
        }
        func components(_ path: String) throws -> [String] {
            let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") && !$0.contains(":") && $0.utf8.count <= 120 && !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }) else { throw Failure.invalidPath }
            return parts
        }
        func ensureDirectory(_ parts: [String]) throws -> Data {
            var path = ""
            var parent = Data()
            for part in parts {
                let next = path.isEmpty ? part : path + "/" + part
                if let known = directoryIDs[next] { parent = known; path = next; continue }
                guard !names.contains(next) else { throw Failure.duplicatePath }
                let id = Data(UUID().uuidString.utf8)
                let name = try cryptor.encryptFileName(part, dirId: parent) + ".c9r"
                let entry = try directory(parent).appendingPathComponent(name)
                try FileManager.default.createDirectory(at: entry, withIntermediateDirectories: false)
                try id.write(to: entry.appendingPathComponent("dir.c9r"))
                try FileManager.default.createDirectory(at: directory(id), withIntermediateDirectories: true)
                directoryIDs[next] = id
                parent = id
                path = next
            }
            return parent
        }
        func add(path: String, bytes: Data, workspace: URL, includeInManifest: Bool = true) async throws {
            let parts = try components(path)
            guard names.insert(path).inserted, directoryIDs[path] == nil else { throw Failure.duplicatePath }
            let parent = try ensureDirectory(Array(parts.dropLast()))
            let name = try cryptor.encryptFileName(parts.last!, dirId: parent) + ".c9r"
            let encrypted = try directory(parent).appendingPathComponent(name)
            let source = workspace.appendingPathComponent(UUID().uuidString)
            try bytes.write(to: source)
            defer { try? FileManager.default.removeItem(at: source) }
            try await cryptor.encryptContent(from: source, to: encrypted)
            encryptedPaths[path] = String(encrypted.path.dropFirst(root.path.count + 1))
            if includeInManifest { files.append(["path": path, "bytes": bytes.count, "sha256": hash(bytes)]) }
        }
        func finish(workspace: URL, nested: [String] = []) async throws {
            let manifest: [String: Any] = [
                "schema": "waglock-portable-export-experiment-1",
                "fixtureOnly": true,
                "files": files.sorted { ($0["path"] as! String) < ($1["path"] as! String) },
                "directories": directoryIDs.keys.filter { !$0.isEmpty }.sorted(),
                "nestedVaults": nested,
            ]
            try await add(path: manifestName, bytes: json(manifest), workspace: workspace, includeInManifest: false)
        }
    }

    static func main() async throws {
        guard CommandLine.arguments.count == 2 else { throw Failure.usage }
        let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw Failure.destinationExists }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        // All preparation is inside this newly owned workspace; the final vault is published last.
        let stage = destination.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        do {
            let inner = try Builder(root: stage.appendingPathComponent("inner-vault"), password: innerPassword)
            let secret = Data((0..<73_113).map { UInt8(($0 * 7) % 251) })
            try await inner.add(path: "Photos/secret.bin", bytes: secret, workspace: stage)
            try await inner.finish(workspace: stage)
            let outer = try Builder(root: stage.appendingPathComponent("outer-vault"), password: outerPassword)
            let original = Data((0..<(65_536 + 37)).map { UInt8($0 % 251) })
            try await outer.add(path: "Trips/2026/sample.bin", bytes: original, workspace: stage)
            try await outer.add(path: "Readme.txt", bytes: Data("Public disposable WagLock export experiment.\n".utf8), workspace: stage)
            try await outer.add(path: "Trips/café.txt", bytes: Data("Unicode names and bytes are preserved. 家族\n".utf8), workspace: stage)
            guard let enumerator = FileManager.default.enumerator(at: inner.root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { throw Failure.invalidPath }
            let urls = enumerator.compactMap { $0 as? URL }.sorted { $0.path < $1.path }
            for source in urls {
                let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { throw Failure.invalidPath }
                if values.isRegularFile == true {
                    let relative = String(source.path.dropFirst(inner.root.path.count + 1))
                    try await outer.add(path: "Protected/" + relative, bytes: Data(contentsOf: source), workspace: stage)
                }
            }
            try await outer.finish(workspace: stage, nested: ["Protected"])
            let report: [String: Any] = [
                "fixtureOnly": true, "schema": "waglock-export-experiment-1", "vaultFormat": 8,
                "swiftLibraryRevision": "b339c9ba84f7737377ef187a78900f9cc384cb12",
                "outerPassword": outerPassword, "innerPassword": innerPassword,
                "expectedOuterSHA256": hash(original), "expectedInnerSHA256": hash(secret),
                "truncationTarget": outer.encryptedPaths["Trips/2026/sample.bin"]!,
                "manifestCiphertext": outer.encryptedPaths[manifestName]!,
                "wholeVaultExportImplemented": false, "phoneLibraryRead": false,
            ]
            // No secret inner data is published unencrypted, apart from reproducible public fixture definitions.
            try FileManager.default.moveItem(at: outer.root, to: destination.appendingPathComponent("candidate-vault"))
            try json(report).write(to: destination.appendingPathComponent("experiment.json"), options: .atomic)
            try FileManager.default.removeItem(at: stage)
            print("Disposable nested-vault candidate published. Verify with an independent reader; no app integration is enabled.")
        } catch {
            try? FileManager.default.removeItem(at: stage)
            throw error
        }
    }
}
