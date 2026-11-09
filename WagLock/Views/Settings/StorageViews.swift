import SwiftUI

// Fixed-size storage screens. All of them are app-wide and render the same in every
// library. None shows how much WagLock or any library uses: only the chosen size, free
// space on the iPhone, a percentage and time left.

private func gigabytes(_ bytes: Int64) -> String { "\(bytes / StorageReserve.gigabyte) GB" }

private func freeOnIPhone(_ reserve: StorageReserve) -> String {
    let free = (try? StorageReserve.deviceFreeSpace(reserve.reserveURL.deletingLastPathComponent())) ?? 0
    return gigabytes(free) + " free on this iPhone"
}

/// Settings › Storage, storage-mode card.
struct StorageModeSection: View {
    @EnvironmentObject private var storage: StorageReserveCoordinator
    @State private var sizeSheet = false
    @State private var confirmStandard = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WagLockSectionLabel("Storage mode · All of WagLock")
            VStack(alignment: .leading, spacing: 8) {
                if storage.mode == .fixed {
                    Text("Fixed size").font(.wlHeading).foregroundStyle(Graphite.textPrimary)
                    Text("\(storage.targetGigabytes) GB reserved on this iPhone").font(.wlBodyStrong).foregroundStyle(Graphite.accentText)
                    Text("WagLock’s size stays the same however much you add, so it gives nothing away.")
                        .font(.wlMeta).foregroundStyle(Graphite.textSecondary)
                    if storage.phase == .paused || storage.phase == .allocating {
                        Label("Still reserving space · \(Int(storage.progress * 100))%", systemImage: "hourglass")
                            .font(.wlMeta).foregroundStyle(Graphite.warn)
                    }
                } else {
                    Text("Standard").font(.wlHeading).foregroundStyle(Graphite.textPrimary)
                    Text("Grows as you add things and uses only the space you need.")
                        .font(.wlMeta).foregroundStyle(Graphite.textSecondary)
                    Label("Your iPhone’s storage settings show how much WagLock holds.", systemImage: "info.circle")
                        .font(.wlMeta).foregroundStyle(Graphite.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(Graphite.surface1, in: RoundedRectangle(cornerRadius: 16))
            if storage.mode == .fixed {
                Button { sizeSheet = true } label: {
                    WagLockRow(symbol: "arrow.up.left.and.arrow.down.right", title: "Change size…", detail: freeOnIPhone(storage.reserve))
                }.buttonStyle(.plain).accessibilityIdentifier("storage.changeSize")
                Button { confirmStandard = true } label: {
                    WagLockRow(symbol: "arrow.left.arrow.right", title: "Switch to Standard", detail: "Releases the reserved space")
                }.buttonStyle(.plain).accessibilityIdentifier("storage.standard")
                WagLockNote(kind: .caution, text: "Any size change is visible on your iPhone. Switching to Standard shows WagLock’s real size in iOS storage settings.")
            } else {
                Button { sizeSheet = true } label: {
                    WagLockRow(symbol: "lock.square.stack", title: "Switch to fixed size…",
                               detail: "Reserve space up front so WagLock’s size never hints at what’s inside")
                }.buttonStyle(.plain).accessibilityIdentifier("storage.fixed")
            }
            if let error { WagLockNote(kind: .error, text: error) }
        }
        .sheet(isPresented: $sizeSheet) { StorageSizeSheet() }
        .confirmationDialog("Switch to Standard?", isPresented: $confirmStandard, titleVisibility: .visible) {
            Button("Switch to Standard", role: .destructive) {
                do { try storage.useStandard(); error = nil }
                catch { self.error = "WagLock couldn’t release the reserved space. Nothing else changed. Try again." }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The reserved space is released. Nothing you’ve saved changes, but iOS storage settings will show WagLock’s real size.")
        }
    }
}

/// Size choice: 8 GB, 32 GB or custom 2–180 GB, bounded by free space on this iPhone.
struct StorageSizeSheet: View {
    @EnvironmentObject private var storage: StorageReserveCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var choice = 8
    @State private var custom = 16
    @State private var useCustom = false
    @State private var error: String?
    var onDone: () -> Void = {}

    private var chosen: Int { useCustom ? custom : choice }
    private var largest: Int { max(2, Int(storage.reserve.largestAllowedBytes() / StorageReserve.gigabyte)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WagLockSheetHeader(title: storage.mode == .fixed ? "Change size" : "Fixed size") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    WagLockTitle(text: "Reserve space", size: .sheet)
                    Text("WagLock sets aside this much space on your iPhone. Its size then stays the same however much you add or how many passcodes exist.")
                        .font(.wlBody).foregroundStyle(Graphite.textMuted).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        preset(8); preset(32)
                        WagLockChip(title: "Custom", selected: useCustom) { useCustom = true }
                    }
                    if useCustom {
                        HStack {
                            Button { custom = max(2, custom - 1) } label: { Image(systemName: "minus").frame(width: 44, height: 44) }
                                .accessibilityLabel("Smaller")
                            Spacer()
                            Text("\(custom) GB").font(.wlTitle).foregroundStyle(Graphite.textPrimary).monospacedDigit()
                            Spacer()
                            Button { custom = min(largest, custom + 1) } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                                .accessibilityLabel("Larger")
                        }
                        .foregroundStyle(Graphite.accentText)
                        .padding(8).background(Graphite.surface1, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityElement(children: .combine)
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment: custom = min(largest, custom + 1)
                            case .decrement: custom = max(2, custom - 1)
                            @unknown default: break
                            }
                        }
                    }
                    Text("2–\(min(180, largest)) GB · " + freeOnIPhone(storage.reserve)).font(.wlMeta).foregroundStyle(Graphite.textMuted)
                    WagLockNote(kind: .caution, text: "The reserved space is used even while empty. Growing it later is a visible jump in size. Up to 16 passcodes fit in either mode.")
                    if let error { WagLockNote(kind: .error, text: error) }
                }
            }
            Button("Reserve \(chosen) GB") { apply() }
                .buttonStyle(WagLockPrimaryButtonStyle())
                .disabled(chosen > largest || (storage.mode == .fixed && chosen == storage.targetGigabytes))
                .accessibilityIdentifier("storage.size.confirm")
        }
        .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 24)
        .background(Graphite.base)
        .onAppear {
            if storage.mode == .fixed { custom = storage.targetGigabytes; useCustom = ![8, 32].contains(custom); choice = custom }
        }
    }

    private func preset(_ value: Int) -> some View {
        WagLockChip(title: "\(value) GB", selected: !useCustom && choice == value) { useCustom = false; choice = value }
            .disabled(value > largest).opacity(value > largest ? 0.5 : 1)
    }

    private func apply() {
        do {
            try storage.useFixedSize(gigabytes: chosen)
            onDone(); dismiss()
        } catch StorageReserve.Failure.insufficientDevice {
            error = "This iPhone doesn’t have enough free space for that size. Choose a smaller size or free some space."
        } catch StorageReserve.Failure.invalidSize {
            error = "That size is too small for what WagLock already holds. Choose a larger size."
        } catch {
            self.error = "WagLock couldn’t change its storage. Nothing changed. Try again."
        }
    }
}

/// Switching storage: percentage and time left only, never bytes.
struct StorageSwitchingView: View {
    @EnvironmentObject private var storage: StorageReserveCoordinator

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle().stroke(Graphite.surface2, lineWidth: 10)
                Circle().trim(from: 0, to: storage.progress)
                    .stroke(Graphite.accentGradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(Int(storage.progress * 100))%").font(.wlDisplay).foregroundStyle(Graphite.textPrimary)
                    if let left = storage.secondsLeft {
                        Text(left < 90 ? "less than 2 min left" : "about \(left / 60) min left")
                            .font(.wlMeta).foregroundStyle(Graphite.textMuted)
                    }
                }
            }
            .frame(width: 200, height: 200)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Reserving space, \(Int(storage.progress * 100)) percent")
            WagLockTitle(text: "Switching to fixed size", size: .sheet).multilineTextAlignment(.center)
            Text("WagLock is reserving its space. Your libraries aren’t moved or changed.")
                .font(.wlBody).foregroundStyle(Graphite.textMuted).multilineTextAlignment(.center)
            switch storage.phase {
            case .failed(let message): WagLockNote(kind: .error, text: message)
            case .paused: WagLockNote(kind: .info, text: "Paused. WagLock picks up where it stopped next time you open it.")
            default:
                WagLockNote(kind: .caution, text: "Keep WagLock open and your iPhone charging. If it’s interrupted, WagLock picks up where it stopped next time you open it.")
            }
            Spacer()
            if storage.phase == .allocating {
                Button("Pause") { storage.pause() }.buttonStyle(WagLockSecondaryButtonStyle())
                    .accessibilityIdentifier("storage.switching.pause")
            } else {
                Button("Resume") { storage.resume() }.buttonStyle(WagLockPrimaryButtonStyle())
                    .accessibilityIdentifier("storage.switching.resume")
                Button("Not now") { storage.dismissSwitching() }
                    .font(WagLockFonts.poppins(14, .semibold, relativeTo: .body))
                    .foregroundStyle(Graphite.textSecondary).frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(.horizontal, 24).padding(.bottom, 24)
        .background(Graphite.base.ignoresSafeArea())
        .interactiveDismissDisabled(storage.phase == .allocating)
    }
}

/// Reserved space is full. Can appear in any library; never shows how much each uses.
struct StorageFullView: View {
    @EnvironmentObject private var storage: StorageReserveCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var sizeSheet = false
    @State private var confirmStandard = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 20)
            Image(systemName: "externaldrive.badge.exclamationmark").font(.system(size: 30)).foregroundStyle(Graphite.warn)
                .frame(width: 64, height: 64).background(Graphite.warnTint, in: Circle()).accessibilityHidden(true)
            WagLockTitle(text: "Reserved space is full", size: .sheet)
            Text("New items can’t be added until there’s room. Nothing you’ve already saved is affected.")
                .font(.wlBody).foregroundStyle(Graphite.textMuted).fixedSize(horizontal: false, vertical: true)
            Button { sizeSheet = true } label: {
                WagLockRow(symbol: "arrow.up.left.and.arrow.down.right", title: "Grow reserved space",
                           detail: "Pick a new size · " + freeOnIPhone(storage.reserve))
            }.buttonStyle(.plain).accessibilityIdentifier("storageFull.grow")
            Button { dismiss() } label: {
                WagLockRow(symbol: "trash", title: "Free up space here", detail: "Delete or export items you no longer need in this library")
            }.buttonStyle(.plain).accessibilityIdentifier("storageFull.free")
            Button { confirmStandard = true } label: {
                WagLockRow(symbol: "arrow.left.arrow.right", title: "Switch to Standard", detail: "Grows as needed · Nothing is copied or deleted")
            }.buttonStyle(.plain).accessibilityIdentifier("storageFull.standard")
            WagLockNote(kind: .info, text: "This can appear in any library, because space is shared across WagLock. It never shows how much each library uses.")
            if let error { WagLockNote(kind: .error, text: error) }
            Spacer()
            Button("Not now") { dismiss() }
                .font(WagLockFonts.poppins(14, .semibold, relativeTo: .body))
                .foregroundStyle(Graphite.textSecondary).frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("storageFull.dismiss")
        }
        .padding(.horizontal, 22).padding(.bottom, 20)
        .background(Graphite.base.ignoresSafeArea())
        .sheet(isPresented: $sizeSheet) { StorageSizeSheet(onDone: { dismiss() }) }
        .confirmationDialog("Switch to Standard?", isPresented: $confirmStandard, titleVisibility: .visible) {
            Button("Switch to Standard", role: .destructive) {
                do { try storage.useStandard(); dismiss() }
                catch { self.error = "WagLock couldn’t release the reserved space. Nothing else changed. Try again." }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("iOS storage settings will show WagLock’s real size.")
        }
    }
}

/// Onboarding step 2: storage privacy. The choice is applied after the first library opens.
struct OnboardingStorageView: View {
    @Binding var fixedGigabytes: Int?
    let next: () -> Void
    @State private var fixed = false
    @State private var choice = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    WagLockTitle(text: "How private should storage be?").padding(.top, 40)
                    Text("Both options encrypt everything. You can change this later in Settings.")
                        .font(.wlBody).foregroundStyle(Graphite.textMuted)
                    option(selected: !fixed, title: "Standard", badge: "Most people",
                           detail: "Grows as you add things and uses only the space you need.",
                           caveats: ["Your iPhone’s storage settings show how much WagLock holds."]) { fixed = false }
                        .accessibilityIdentifier("onboarding.storage.standard")
                    option(selected: fixed, title: "Fixed size", badge: nil,
                           detail: "Reserves space up front, so WagLock’s size never hints at what’s inside or how many passcodes exist.",
                           caveats: ["The reserved space is used even while empty.", "Growing it later is a visible jump in size."]) { fixed = true }
                        .accessibilityIdentifier("onboarding.storage.fixed")
                    if fixed {
                        HStack(spacing: 8) {
                            ForEach([8, 32], id: \.self) { value in
                                WagLockChip(title: "\(value) GB", selected: choice == value) { choice = value }
                            }
                        }
                        Text("Other sizes (2–180 GB) are in Settings › Storage · " + freeOnIPhone(.shared))
                            .font(.wlMeta).foregroundStyle(Graphite.textMuted)
                    }
                    Text("Either way, room for up to 16 passcodes is built in. It takes a few kilobytes.")
                        .font(.wlMeta).foregroundStyle(Graphite.textMuted)
                }
            }
            Button("Continue") { fixedGigabytes = fixed ? choice : nil; next() }
                .buttonStyle(WagLockPrimaryButtonStyle()).accessibilityIdentifier("onboarding.storage.continue")
        }
        .padding(.horizontal, 24).padding(.bottom, 24)
    }

    private func option(selected: Bool, title: String, badge: String?, detail: String, caveats: [String],
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 20)).foregroundStyle(selected ? Graphite.accentText : Graphite.line)
                    Text(title).font(.wlHeading).foregroundStyle(Graphite.textPrimary)
                    if let badge {
                        Text(badge).font(WagLockFonts.poppins(11, .semibold, relativeTo: .caption))
                            .foregroundStyle(Graphite.accentText).padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Graphite.accentTint, in: Capsule())
                    }
                    Spacer()
                }
                Text(detail).font(.wlMeta).foregroundStyle(Graphite.textSecondary).fixedSize(horizontal: false, vertical: true)
                ForEach(caveats, id: \.self) { caveat in
                    Text("– " + caveat).font(.wlMeta).foregroundStyle(Graphite.textMuted)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Graphite.surface1, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Graphite.accentText.opacity(0.6) : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
