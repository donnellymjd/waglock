//
//  PhotoPickerRepresentable.swift
//  WagLock
//
//  SwiftUI bridge for PHPickerViewController
//  Used to pick photos and videos
//

import PhotosUI
import SwiftUI

/// PHPicker result
struct PhotoPickerResult {
    let itemProvider: NSItemProvider
    let assetIdentifier: String?
}

/// SwiftUI representable for the photo picker
struct PhotoPickerRepresentable: UIViewControllerRepresentable {

    // MARK: - Properties

    @Binding var isPresented: Bool
    let selectionLimit: Int
    let filter: PHPickerFilter
    let onSelect: ([PHPickerResult]) -> Void

    // MARK: - Initialization

    init(
        isPresented: Binding<Bool>,
        selectionLimit: Int = 0,  // 0 = unlimited
        filter: PHPickerFilter = .any(of: [.images, .videos]),
        onSelect: @escaping ([PHPickerResult]) -> Void
    ) {
        self._isPresented = isPresented
        self.selectionLimit = selectionLimit
        self.filter = filter
        self.onSelect = onSelect
    }

    // MARK: - UIViewControllerRepresentable

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.selectionLimit = selectionLimit
        configuration.filter = filter
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        // No update needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPickerRepresentable

        init(_ parent: PhotoPickerRepresentable) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.isPresented = false

            if !results.isEmpty {
                parent.onSelect(results)
            }
        }
    }
}

// MARK: - Document Picker Representable

/// SwiftUI representable for the document picker
struct DocumentPickerRepresentable: UIViewControllerRepresentable {

    // MARK: - Properties

    @Binding var isPresented: Bool
    let contentTypes: [UTType]
    let allowsMultipleSelection: Bool
    let onSelect: ([URL]) -> Void

    // MARK: - Initialization

    init(
        isPresented: Binding<Bool>,
        contentTypes: [UTType] = [.item],
        allowsMultipleSelection: Bool = true,
        onSelect: @escaping ([URL]) -> Void
    ) {
        self._isPresented = isPresented
        self.contentTypes = contentTypes
        self.allowsMultipleSelection = allowsMultipleSelection
        self.onSelect = onSelect
    }

    // MARK: - UIViewControllerRepresentable

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes)
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController, context: Context
    ) {
        // No update needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPickerRepresentable

        init(_ parent: DocumentPickerRepresentable) {
            self.parent = parent
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]
        ) {
            parent.isPresented = false
            parent.onSelect(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.isPresented = false
        }
    }
}
