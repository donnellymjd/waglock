import SwiftUI

/// Mounts ContentView's model environment only for the currently authenticated session.
struct AuthenticatedLibraryView: View {
    @EnvironmentObject private var authentication: AuthenticationViewModel
    @EnvironmentObject private var mode: GuestModeManager
    @StateObject private var library: LibraryMountCoordinator
    let services: VaultSessionContext
    init(services: VaultSessionContext, library: LibraryMountCoordinator) {
        self.services = services
        _library = StateObject(wrappedValue: library)
    }
    @State private var retry = UUID()

    private var request: LibraryMountCoordinator.Request {
        .init(sessionID: authentication.librarySessionID,
              scope: mode.isOwnerMode ? authentication.libraryScope : .ephemeralGuest)
    }

    var body: some View {
        let expected = request
        Group {
            if let mounted = library.active, mounted.request == expected {
                ContentView()
                    .environmentObject(library)
                    .environmentObject(services)
                    .environmentObject(services.albums)
                    .environmentObject(services.exports)
                    .environmentObject(services.audio)
                    .environmentObject(services.backupReminders)
                    .modelContainer(mounted.container)
                    .id(mounted.id)
            } else if library.failed {
                VStack(spacing: 14) {
                    Spacer()
                    Image(systemName: "exclamationmark.circle").font(.system(size: 40)).foregroundStyle(Graphite.warn)
                        .frame(width: 88, height: 88)
                        .background(Graphite.surface1, in: RoundedRectangle(cornerRadius: 26))
                        .overlay(RoundedRectangle(cornerRadius: 26).stroke(Graphite.line, lineWidth: 1))
                        .accessibilityHidden(true)
                    VStack(spacing: 6) {
                        Text("Unable to open this library.").font(.wlSheetTitle).foregroundStyle(Graphite.textPrimary)
                            .multilineTextAlignment(.center).wlCappedDisplay()
                        Text("Lock and try again. Your library and passcodes haven’t been reset.")
                            .font(WagLockFonts.poppins(13, .regular, relativeTo: .footnote))
                            .foregroundStyle(Graphite.textMuted).multilineTextAlignment(.center)
                    }
                    if let reference = library.failureReference {
                        Text("REFERENCE " + reference.uppercased())
                            .font(.wlLabel).tracking(1).foregroundStyle(Graphite.textMuted)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Graphite.surface1, in: RoundedRectangle(cornerRadius: 10))
                            .accessibilityLabel("Reference: " + reference)
                            .accessibilityIdentifier("library.mount.reference")
                    }
                    Spacer()
                    Button("Retry") { retry = UUID() }.buttonStyle(WagLockPrimaryButtonStyle())
                    Button("Lock WagLock") { authentication.logout() }
                        .font(WagLockFonts.poppins(14, .semibold, relativeTo: .body))
                        .foregroundStyle(Color(hex: 0xC9CFDB)).frame(minHeight: 44)
                }
                .padding(.horizontal, 22).padding(.vertical, 30)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Graphite.base)
                .accessibilityIdentifier("library.mount.error")
            } else {
                ProgressView("Opening library…").tint(Graphite.accentText)
                    .font(.wlBody).foregroundStyle(Graphite.textMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Graphite.base)
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
