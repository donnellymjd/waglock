import Foundation

/// Immutable display/read metadata captured while the originating library is mounted.
/// A dismissed screen must never fault a SwiftData record after logout closes its store.
struct MediaPreviewSnapshot {
    let id: UUID
    let fileName: String
    let fileExtension: String
    let encryptedPath: String
    let type: MediaType
    let fullFileName: String
    let formattedFileSize: String
    let formattedDimensions: String?
    let formattedDuration: String?
    let duration: Double?
    let formattedCreatedDate: String

    @MainActor
    init(_ item: MediaItem) {
        id = item.id
        fileName = item.fileName
        fileExtension = item.fileExtension
        encryptedPath = item.encryptedPath
        type = item.type
        fullFileName = item.fullFileName
        formattedFileSize = item.formattedFileSize
        formattedDimensions = item.formattedDimensions
        formattedDuration = item.formattedDuration
        duration = item.duration
        formattedCreatedDate = item.formattedCreatedDate
    }
}
