//
//  PhotosViewModel.swift
//  WagLock
//
//  Photos view model
//

import Foundation
import SwiftUI

@MainActor
class PhotosViewModel: ObservableObject {
    @Published var selectedSortOrder: MediaItem.SortOrder = .dateNewest
    @Published var isLoading = false
}
