import CryptoKit
import CryptomatorCryptoLib
import Foundation

/// Disposable fixtures only. No app container, Keychain, credentials or real media are read.
@main
struct Probe {
    static let password = "Vaultito disposable fixture only"
    static let fixture = Data((0..<(65_536 + 37)).map { UInt8($0 % 251) })

    enum Failure: Error { case assertion(String), usage, destinationExists }

    static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure.assertion(message) }
    }

    static func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
    }

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func directory(_ id: Data, cryptor: Cryptor, vault: URL) throws -> URL {
        let hash = try cryptor.encryptDirId(id)
        return vault.appendingPathComponent("d").appendingPathComponent(String(hash.prefix(2)))
            .appendingPathComponent(String(hash.dropFirst(2)))
    }

    static func makeDirectory(_ name: String, parent: Data, cryptor: Cryptor, vault: URL) throws -> Data {
        let id = Data(UUID().uuidString.utf8)
        let entry = try directory(parent, cryptor: cryptor, vault: vault)
            .appendingPathComponent(cryptor.encryptFileName(name, dirId: parent) + ".c9r")
        try FileManager.default.createDirectory(at: entry, withIntermediateDirectories: true)
        try id.write(to: entry.appendingPathComponent("dir.c9r"))
        try FileManager.default.createDirectory(at: directory(id, cryptor: cryptor, vault: vault), withIntermediateDirectories: true)
        return id
    }

    static func createFixture(in workspace: URL) async throws {
        let vault = workspace.appendingPathComponent("candidate-vault")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let key = try Masterkey.createNew()
        let wrapped = try MasterkeyFile.lock(masterkey: key, vaultVersion: 999, passphrase: password)
        try wrapped.write(to: vault.appendingPathComponent("masterkey.cryptomator"))
        let header = try json(["kid": "masterkeyfile:masterkey.cryptomator", "typ": "JWT", "alg": "HS256"])
        let payload = try json(["format": 8, "shorteningThreshold": 220,
                                "jti": UUID().uuidString, "cipherCombo": "SIV_GCM"])
        let signingInput = base64url(header) + "." + base64url(payload)
        var raw = key.rawKey
        defer { for index in raw.indices { raw[index] = 0 } }
        let signature = HMAC<SHA256>.authenticationCode(for: Data(signingInput.utf8), using: SymmetricKey(data: raw))
        let token = signingInput + "." + base64url(Data(signature))
        try Data(token.utf8).write(to: vault.appendingPathComponent("vault.cryptomator"))
        let cryptor = Cryptor(masterkey: key, scheme: .sivGcm)
        try FileManager.default.createDirectory(at: directory(Data(), cryptor: cryptor, vault: vault), withIntermediateDirectories: true)
        let parent = try makeDirectory("Trips", parent: Data(), cryptor: cryptor, vault: vault)
        let child = try makeDirectory("2026", parent: parent, cryptor: cryptor, vault: vault)
        let original = workspace.appendingPathComponent("expected.bin")
        try fixture.write(to: original)
        let encrypted = try directory(child, cryptor: cryptor, vault: vault)
            .appendingPathComponent(cryptor.encryptFileName("sample.bin", dirId: child) + ".c9r")
        try await cryptor.encryptContent(from: original, to: encrypted)
        // All original key objects go out of scope before the recovery pass.
    }

    static func find(_ name: String, parent: Data, cryptor: Cryptor, vault: URL) throws -> URL {
        try directory(parent, cryptor: cryptor, vault: vault)
            .appendingPathComponent(cryptor.encryptFileName(name, dirId: parent) + ".c9r")
    }

    static func main() async throws {
        guard CommandLine.arguments.count == 2 else { throw Failure.usage }
        let workspace = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        guard !FileManager.default.fileExists(atPath: workspace.path) else { throw Failure.destinationExists }
        try await createFixture(in: workspace)
        let vault = workspace.appendingPathComponent("candidate-vault")
        let keyFile = try MasterkeyFile.withContentFromURL(url: vault.appendingPathComponent("masterkey.cryptomator"))
        do { _ = try keyFile.unlock(passphrase: "wrong password"); throw Failure.assertion("wrong password accepted") }
        catch MasterkeyFileError.invalidPassphrase { }
        let restored = try keyFile.unlock(passphrase: password)
        let cryptor = Cryptor(masterkey: restored, scheme: .sivGcm)
        let parentEntry = try find("Trips", parent: Data(), cryptor: cryptor, vault: vault)
        let parentID = try Data(contentsOf: parentEntry.appendingPathComponent("dir.c9r"))
        let childEntry = try find("2026", parent: parentID, cryptor: cryptor, vault: vault)
        let childID = try Data(contentsOf: childEntry.appendingPathComponent("dir.c9r"))
        let encrypted = try find("sample.bin", parent: childID, cryptor: cryptor, vault: vault)
        let decryptedName = try cryptor.decryptFileName(encrypted.deletingPathExtension().lastPathComponent, dirId: childID)
        try require(decryptedName == "sample.bin", "filename did not round-trip")
        let recovered = workspace.appendingPathComponent("recovered.bin")
        try await cryptor.decryptContent(from: encrypted, to: recovered)
        try require(try Data(contentsOf: recovered) == fixture, "content did not round-trip")

        let corrupted = workspace.appendingPathComponent("tampered.c9r")
        var bytes = try Data(contentsOf: encrypted)
        bytes[bytes.count - 1] ^= 1
        try bytes.write(to: corrupted)
        let partial = workspace.appendingPathComponent("tampered-output.bin")
        defer { try? FileManager.default.removeItem(at: partial) }
        do { try await cryptor.decryptContent(from: corrupted, to: partial); throw Failure.assertion("tampering accepted") }
        catch CryptoKitError.authenticationFailure { }

        // Keep this negative result visible: removing a complete final chunk leaves
        // a valid prefix. Do not equate per-chunk authentication with file completeness.
        let truncated = workspace.appendingPathComponent("truncated.c9r")
        let full = try Data(contentsOf: encrypted)
        try full.dropLast(37 + 12 + 16).write(to: truncated)
        let prefix = workspace.appendingPathComponent("truncated-output.bin")
        try await cryptor.decryptContent(from: truncated, to: prefix)
        let prefixBytes = try Data(contentsOf: prefix)
        try require(prefixBytes == fixture.prefix(65_536), "unexpected truncation result")

        let report: [String: Any] = [
            "libraryRevision": "b339c9ba84f7737377ef187a78900f9cc384cb12",
            "candidateVaultFormat": 8, "cipherCombo": "SIV_GCM",
            "fixturePassword": password, "cleartextPath": "Trips/2026/sample.bin",
            "expectedSHA256": SHA256.hash(data: fixture).map { String(format: "%02x", $0) }.joined(),
            "sourceBytes": fixture.count, "restoredWithoutKeychain": true,
            "wrongPasswordRejected": true, "payloadTamperingRejected": true,
            "wholeFinalChunkRemovalDetected": false,
            "unmodifiedDesktopClientValidated": false,
        ]
        try json(report).write(to: workspace.appendingPathComponent("report.json"))
        print("Disposable candidate vault and report written to " + workspace.path)
        print("Library checks passed. Whole-final-chunk removal was NOT detected; desktop-client interoperability remains unvalidated.")
    }
}
