//
//  AVAudioSession+VideoPlayback.swift
//  WagLock
//
//  Audio session configuration for video playback
//

import AVFoundation

extension AVAudioSession {

    /// Activation count: an inline preview and the full-screen player may both hold the session; it is deactivated only when the last one releases it.
    /// Main-thread access only (every call site is a view lifecycle method).
    private static var playbackActivationCount = 0

    /// Configure and activate the audio session for video playback.
    ///
    /// Uses the `.playback` category so sound plays regardless of the silent switch;
    /// callers must pause playback when the app goes to the background so audio doesn't continue.
    static func activateForVideoPlayback() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            if playbackActivationCount == 0 {
                try session.setActive(true)
            }
            playbackActivationCount += 1
        } catch {
        }
    }

    /// Release the audio session after video playback; it is deactivated only when no player still holds it,
    /// so closing one player doesn't silence another that is still playing.
    static func deactivateAfterVideoPlayback() {
        playbackActivationCount = max(0, playbackActivationCount - 1)
        guard playbackActivationCount == 0 else { return }
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation)
    }
}
