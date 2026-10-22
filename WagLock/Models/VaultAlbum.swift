import Foundation
import SwiftData

enum AlbumProtection: String, Codable, CaseIterable, Identifiable {
    case inherited
    case password
    case passwordAndFaceID
    case faceIDOnly

    var id: String { rawValue }
    var title: String {
        switch self {
        case .inherited: return "Inherit parent protection"
        case .password: return "Album password"
        case .passwordAndFaceID: return "Album password or Face ID"
        case .faceIDOnly: return "Face ID only"
        }
    }
    var requiresPassword: Bool { self == .password || self == .passwordAndFaceID }
    var usesBiometrics: Bool { self == .passwordAndFaceID || self == .faceIDOnly }
}

/// Public album names/hierarchy; media names and thumbnails live inside encryptedCatalog.
/// Album media never enters the legacy, globally queried MediaItem table.
@Model
final class VaultAlbum {
    var id: UUID
    var parentID: UUID?
    var name: String
    var protectionRawValue: String
    var wrappedKey: Data
    var encryptedCatalog: Data
    var biometricAccount: String?
    var createdAt: Date

    init(id: UUID = UUID(), parentID: UUID?, name: String, protection: AlbumProtection,
         wrappedKey: Data, encryptedCatalog: Data, biometricAccount: String? = nil) {
        self.id = id
        self.parentID = parentID
        self.name = name
        self.protectionRawValue = protection.rawValue
        self.wrappedKey = wrappedKey
        self.encryptedCatalog = encryptedCatalog
        self.biometricAccount = biometricAccount
        self.createdAt = Date()
    }
}

struct AlbumAsset: Codable, Identifiable {
    var id: UUID
    var fileName: String
    var encryptedPath: String
    var fileSize: Int64
    var type: MediaType
    var thumbnail: Data?
    var createdAt: Date

    var fileExtension: String { (fileName as NSString).pathExtension }
}
