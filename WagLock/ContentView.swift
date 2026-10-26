//
//  ContentView.swift
//  WagLock
//
//  Main content view (shown after authentication)
//  Uses MainTabView to present the tab bar interface
//

import SwiftData
import SwiftUI

struct ContentView: View {

    @EnvironmentObject var authViewModel: AuthenticationViewModel

    var body: some View {
        MainTabView()
            .environmentObject(authViewModel)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: MediaItem.self, inMemory: true)
}
