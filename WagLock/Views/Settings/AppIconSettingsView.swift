import SwiftUI

struct AppIconSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var auth: AuthenticationViewModel
    @EnvironmentObject private var guest: GuestModeManager
    @StateObject private var icons = AppIconService()
    @State private var errorMessage: String?

    private var canChange: Bool { auth.isAuthenticated && guest.isOwnerMode }

    var body: some View {
        List {
            Section {
                ForEach(AppIconOption.allCases) { icon in
                    iconRow(icon)
                }
                .disabled(icons.isChanging || !canChange)
            } header: {
                Text(String(localized: "appicon.choose"))
            } footer: {
                Text(String(localized: "appicon.intro"))
            }

            if icons.isChanging {
                Section {
                    ProgressView(String(localized: "appicon.changing"))
                }
            }

            Section {
                Text(String(localized: "appicon.footer"))
                    .font(.footnote).foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
        }
        .wagLockList()
        .tint(brandColor)
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle(String(localized: "appicon.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { icons.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { icons.refresh() }
        }
        .alert(String(localized: "common.error"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var brandColor: Color { ColorTheme.accent }

    private func iconRow(_ icon: AppIconOption) -> some View {
        let selected = icons.selectedIconName == icon.iconName
        return Button {
            select(icon)
        } label: {
            HStack(spacing: 12) {
                Image(icon.previewAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(icon.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(icon.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(brandColor)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("appicon.\(icon.rawValue)")
        .accessibilityLabel(icon.title)
        .accessibilityValue(selected ? String(localized: "appicon.selected") : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func select(_ icon: AppIconOption) {
        guard canChange, !icons.isChanging else { return }
        guard icons.selectedIconName != icon.iconName else { return }
        Task {
            do {
                try await icons.select(icon)
            } catch let error as AppIconService.IconError {
                errorMessage = error.localizedDescription
            } catch {
                errorMessage = String(localized: "appicon.error.failed")
            }
        }
    }
}
