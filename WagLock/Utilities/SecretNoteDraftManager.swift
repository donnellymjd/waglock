import Foundation

struct SecretNoteDraft: Codable {
    let title: String
    let content: String
    let updatedAt: Date
}

/// 草稿属于未落库的私密内容，存 Keychain（仅本机、设备解锁后可用），
/// 不能明文写入 UserDefaults（明文 plist 会进入未加密备份）
final class SecretNoteDraftManager {
    nonisolated deinit { }
    static let shared = SecretNoteDraftManager()
    private let legacyDraftKey = "secretSpace.draft"
    private let keychainService: KeychainService
    private let defaults: UserDefaults

    init(keychainService: KeychainService = .shared, defaults: UserDefaults = .standard) {
        self.keychainService = keychainService
        self.defaults = defaults
        migrateLegacyDraftFromUserDefaults()
    }

    func loadDraft() -> SecretNoteDraft? {
        guard let data = keychainService.loadSecretNoteDraft() else { return nil }
        return try? JSONDecoder().decode(SecretNoteDraft.self, from: data)
    }

    @discardableResult
    func saveDraft(title: String, content: String) -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty || !trimmedContent.isEmpty else {
            clearDraft()
            return true
        }
        let draft = SecretNoteDraft(title: title, content: content, updatedAt: Date())
        guard let data = try? JSONEncoder().encode(draft) else { return false }
        return keychainService.saveSecretNoteDraft(data)
    }

    func clearDraft() {
        keychainService.deleteSecretNoteDraft()
    }

    /// Preserve a conflicting legacy draft. A checked read and exact read-back
    /// are required before removing the duplicate plaintext preferences copy.
    private func migrateLegacyDraftFromUserDefaults() {
        guard let data = defaults.data(forKey: legacyDraftKey),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["title", "content", "updatedAt"],
              (try? JSONDecoder().decode(SecretNoteDraft.self, from: data)) != nil else { return }
        do {
            if let existing = try keychainService.loadSecretNoteDraftChecked() {
                guard existing == data else { return }
            } else {
                guard keychainService.saveSecretNoteDraft(data),
                      try keychainService.loadSecretNoteDraftChecked() == data else { return }
            }
            // Recheck the source too; never clear a newer legacy draft.
            guard defaults.data(forKey: legacyDraftKey) == data else { return }
            defaults.removeObject(forKey: legacyDraftKey)
        } catch {
            // Inaccessibility is not absence or permission to replace either source.
        }
    }
}
