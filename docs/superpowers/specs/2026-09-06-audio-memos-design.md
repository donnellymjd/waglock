# Audio memos

Confirmed by the user: the bottom tabs are Photos, Videos, Audio, Files and Notes; Settings moves to a top-right entry on each main screen.

The Audio screen offers file import, recording, pause/resume, a live level waveform, save/cancel, play/pause, scrubbing, rename and confirmed delete. It reuses the SwiftData MediaItem model with a new audio type, keeping existing rawValue compatibility. Audio previously imported as documents in older versions is shown on the Audio screen for compatibility, without a full database migration.

Saving uses the existing streaming encryption, with no networking and no new dependencies. The recording temporary directory uses complete file protection; plaintext is deleted after a successful save or a cancel. Going to the background ends and saves the recording, and playback stops and deletes the decrypted file; leaving the authenticated session cancels unfinished work. Brief system interruptions pause recording, and the user resumes manually. Failures show an error, and a failed foreground save can be retried. Guest mode shows no real audio and allows no recording or import. Audio follows the existing free item limit.

The first version excludes editing, transcription, cloud sync and continuous background recording. Verification covers type compatibility, a real audio encryption round trip, rejection of invalid files, cleanup on cancel, the build and simulator UI; microphone hardware and incoming-call scenarios remain for physical-device acceptance.
