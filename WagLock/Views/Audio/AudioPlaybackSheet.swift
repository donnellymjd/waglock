import SwiftUI

/// Presentation uses immutable metadata; source actions remain in the authorized parent.
struct AudioPlaybackSheet: View {
    let item: MediaPreviewSnapshot
    @ObservedObject var audio: AudioSessionController
    let onToggle: () -> Void
    let onExport: () -> Void
    @Environment(\.dismiss) private var dismiss
    private var isCurrent: Bool { audio.playingID == item.id }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Audio · \(item.fileExtension.uppercased())").font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                    VStack(spacing: 24) {
                        Image(systemName: "waveform").font(.system(size: 64)).foregroundStyle(ColorTheme.accent).accessibilityHidden(true)
                        Text(item.fileName).font(.title2.bold()).multilineTextAlignment(.center)
                        Text("\(item.formattedDuration ?? "Audio") · \(item.formattedFileSize)").font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                    }.frame(maxWidth: .infinity, minHeight: 240).padding(16)
                        .background(ColorTheme.tertiaryBackground, in: RoundedRectangle(cornerRadius: 24))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(formatTime(isCurrent ? audio.playbackTime : 0)) / \(formatTime(isCurrent ? audio.playbackDuration : 0))")
                            .font(.body.weight(.semibold).monospacedDigit())
                        Text(isCurrent && audio.isPlaying ? "Playing on this device" : "Ready to play").font(.footnote).foregroundStyle(ColorTheme.secondaryText)
                        Slider(value: Binding(get: { isCurrent ? audio.playbackTime : 0 }, set: { if isCurrent { audio.seek(to: $0) } }), in: 0...max(isCurrent ? audio.playbackDuration : 0, 0.1))
                            .tint(ColorTheme.accent).disabled(!isCurrent).accessibilityLabel("Playback progress")
                    }.padding(16).background(ColorTheme.tertiaryBackground, in: RoundedRectangle(cornerRadius: 16))
                    HStack {
                        Button("−15 sec") { if isCurrent { audio.seek(to: max(0, audio.playbackTime - 15)) } }.disabled(!isCurrent)
                        Spacer()
                        Button(isCurrent && audio.isPlaying ? "Pause" : "Play", action: onToggle)
                        Spacer()
                        Button("+15 sec") { if isCurrent { audio.seek(to: min(audio.playbackDuration, audio.playbackTime + 15)) } }.disabled(!isCurrent)
                    }.buttonStyle(.bordered).padding(3).background(ColorTheme.tertiaryBackground, in: RoundedRectangle(cornerRadius: 12))
                    Button("Export audio", action: onExport).buttonStyle(WagLockPrimaryButtonStyle())
                }.padding(24)
            }.background(ColorTheme.primaryBackground).navigationTitle(item.fileName).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("audio.player.close") } }
        }
    }

    private func formatTime(_ time: Double) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(time) / 60, Int(time) % 60)
    }
}
