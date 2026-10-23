import SwiftUI

/// Mounts ContentView's model environment only for the currently authenticated session.
struct AuthenticatedLibraryView: View {
    @EnvironmentObject private var authentication: AuthenticationViewModel
    @EnvironmentObject private var mode: GuestModeManager
    @StateObject private var library = LibraryMountCoordinator()
    @State private var retry = UUID()

    private var request: LibraryMountCoordinator.Request {
        .init(sessionID: authentication.librarySessionID,
              scope: mode.isOwnerMode ? .legacyOwner : .ephemeralGuest)
    }

    var body: some View {
        let expected = request
        Group {
            if let mounted = library.active, mounted.request == expected {
                ContentView()
                    .environmentObject(library)
                    .modelContainer(mounted.container)
                    .id(mounted.id)
            } else if library.failed {
                VStack(spacing: 20) {
                    Text("Unable to open this library.").font(.headline)
                    Text("Lock and try again. Your library and credentials have not been reset.")
                        .multilineTextAlignment(.center)
                    Button("Retry") { retry = UUID() }
                    Button("Lock") { authentication.logout() }
                }
                .padding()
                .accessibilityIdentifier("library.mount.error")
            } else {
                ProgressView("Opening library…")
                    .accessibilityIdentifier("library.mount.loading")
            }
        }
        .task(id: MountTask(request: expected, retry: retry)) {
            await library.mount(expected, dataPassword: authentication.sessionPassword) {
                authentication.isAuthenticated
                    && authentication.librarySessionID == expected.sessionID
                    && mode.currentMode != .unauthenticated
                    && request == expected
            }
        }
        .onDisappear { library.invalidate() }
    }

    private struct MountTask: Hashable {
        let request: LibraryMountCoordinator.Request
        let retry: UUID
    }
}
