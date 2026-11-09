import SwiftUI

/// Presentation uses immutable metadata; source actions remain in the authorized parent.
struct AudioPlaybackSheet: View {
    let item: MediaPreviewSnapshot
    @ObservedObject var audio: AudioSessionController
    let onToggle: () -> Void
    let onExport: () -> Void
    @Environment(\.dismiss) private var dismiss
    private var isCurrent: Bool { audio.playingID == item.id }
    private var playing: Bool { isCurrent && audio.isPlaying }
    private var elapsed: Double { isCurrent ? audio.playbackTime : 0 }
    private var duration: Double { isCurrent ? audio.playbackDuration : (item.duration ?? 0) }
    private var fraction: Double { duration > 0 ? min(max(elapsed / duration, 0), 1) : 0 }

    /// Decorative bars only; the shape is not derived from the audio.
    private static let bars: [CGFloat] = [18, 30, 46, 62, 40, 72, 90, 64, 48, 80, 100, 70, 52, 36, 58, 84, 66, 44, 30, 52, 38, 24, 40, 28, 18]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                WagLockRoundButton(symbol: "xmark", label: "Close") { dismiss() }
                    .accessibilityIdentifier("audio.player.close")
                Spacer()
                Text("AUDIO · \(item.fileExtension.uppercased())").font(.wlLabel).tracking(1.9).foregroundStyle(Graphite.textMuted)
                Spacer()
                WagLockRoundButton(symbol: "square.and.arrow.up", label: "Export audio", action: onExport)
                    .accessibilityIdentifier("audio.player.export")
            }
            HStack(spacing: 4) {
                ForEach(Array(Self.bars.enumerated()), id: \.offset) { index, height in
                    Capsule()
                        .fill(Double(index) / Double(Self.bars.count) < fraction || (!isCurrent && index < 14)
                              ? Graphite.accentText : Graphite.line)
                        .frame(width: 5, height: height)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 240)
            .background(
                RadialGradient(colors: [Graphite.accentStrong.opacity(0.25), .clear], center: .center, startRadius: 0, endRadius: 200),
                in: RoundedRectangle(cornerRadius: 28))
            .background(Color(hex: 0x20242F), in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(Graphite.accentText.opacity(0.14), lineWidth: 1))
            .accessibilityHidden(true)
            .padding(.top, 18)
            VStack(spacing: 2) {
                Text(item.fileName).font(WagLockFonts.poppins(28, .extraBold, relativeTo: .title))
                    .foregroundStyle(Graphite.textPrimary).multilineTextAlignment(.center).wlCappedDisplay()
                Text(([item.formattedDuration, item.formattedFileSize, "Added " + item.createdAt.formatted(.dateTime.month(.abbreviated).day())]
                        .compactMap { $0 }).joined(separator: " · "))
                    .font(WagLockFonts.poppins(13, .regular, relativeTo: .footnote)).foregroundStyle(Graphite.textMuted)
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 8) {
                Slider(value: Binding(get: { elapsed }, set: { if isCurrent { audio.seek(to: $0) } }),
                       in: 0...max(duration, 0.1))
                    .tint(Graphite.accentStrong).disabled(!isCurrent)
                    .accessibilityLabel("Playback position")
                    .accessibilityValue(formatTime(elapsed))
                HStack {
                    Text(formatTime(elapsed))
                    Spacer()
                    Text("−" + formatTime(max(duration - elapsed, 0)))
                }
                .font(WagLockFonts.poppins(12, .medium, relativeTo: .caption).monospacedDigit()).foregroundStyle(Graphite.textMuted)
            }
            HStack(spacing: 34) {
                Button { if isCurrent { audio.seek(to: max(0, audio.playbackTime - 15)) } } label: {
                    Image(systemName: "gobackward.15").font(.system(size: 26)).foregroundStyle(Color(hex: 0xE3E7EF))
                        .frame(width: 52, height: 52)
                }
                .disabled(!isCurrent).accessibilityLabel("Back 15 seconds")
                Button(action: onToggle) {
                    Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 28))
                        .foregroundStyle(Graphite.onAccent)
                        .frame(width: 76, height: 76)
                        .background(LinearGradient(colors: [Graphite.accentLight, Graphite.accentStrong],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                        .shadow(color: Graphite.accentStrong.opacity(0.35), radius: 14, y: 12)
                }
                .accessibilityLabel(playing ? "Pause" : "Play")
                .accessibilityIdentifier("audio.player.toggle")
                Button { if isCurrent { audio.seek(to: min(audio.playbackDuration, audio.playbackTime + 15)) } } label: {
                    Image(systemName: "goforward.15").font(.system(size: 26)).foregroundStyle(Color(hex: 0xE3E7EF))
                        .frame(width: 52, height: 52)
                }
                .disabled(!isCurrent).accessibilityLabel("Forward 15 seconds")
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            WagLockNote(kind: .info, text: "Playback stays inside WagLock. Exporting creates a copy outside it.")
        }
        .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 24)
        .background(Graphite.base.ignoresSafeArea())
    }

    private func formatTime(_ time: Double) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(time) / 60, Int(time) % 60)
    }
}
