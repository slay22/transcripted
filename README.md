# Transcripted

A small native macOS meeting notebook. Record on demand, transcribe after the meeting with Apple's SpeechAnalyzer, and summarize locally with Foundation Models. No API key, server, or third-party dependencies.

## Requirements

- Apple Silicon Mac (M1 or newer), macOS 26 or later.
- Apple Intelligence enabled and its model downloaded for summaries. Transcription is independent of Apple Intelligence availability.
- English, French, or German selected before recording. Language availability is checked at runtime; Apple may download speech assets on first use.
- Swift 6.2+ and a macOS 26+ SDK to build (Xcode or compatible Command Line Tools).

## Build and run

```sh
bash scripts/build-app.sh
open dist/Transcripted.app
```

Run the `.app`, rather than `swift run`, so macOS can associate privacy permissions with the bundle. The build script signs locally with an ad-hoc signature. For a stable signing identity, set `SIGNING_IDENTITY` to an installed Apple Development certificate. Sharing with other Macs needs appropriate signing and notarization; this script produces a local development app.

## Use

1. Choose English, French, or German and an audio source.
2. Press **⌘⇧R** anywhere, or use **Record meeting** in the window/menu bar.
3. Grant microphone access. **Microphone + Mac audio** also requires the system audio/screen-recording permission requested by macOS; after granting it, a restart may be needed.
4. Press **⌘⇧R** again to stop. Transcription and a summary are generated automatically.
5. Open **Transcript**, export Markdown, or retry transcription/summary from the meeting's **…** menu.
6. Use **… → Edit meeting details…** to change the name or date. Use **… → Delete meeting…** to permanently remove a meeting, including its transcript, summary, and audio, after confirmation. These actions are disabled during recording and processing.

The initial shortcut is fixed to ⌘⇧R. If another app has registered it, use the menu bar. Shortcuts are ignored while starting, stopping, or processing. Closing the window leaves the menu-bar app running; quitting is blocked during active work.

**Microphone** is for in-person meetings. **Microphone + Mac audio** captures both sides of online meetings, including all other audio playing on the Mac. Use headphones to avoid echo/duplicate words. This mode saves separate microphone/system tracks and combines transcript segments by time, without speaker labels. No video is saved. If system capture is unavailable, select microphone-only mode explicitly.

## Storage and privacy

Meetings live in `~/Library/Application Support/Transcripted/Meetings/<id>/`:

- `meeting.json`: meeting metadata, timestamped transcript, summary, and last processing error.
- `microphone.caf`, optionally `system.caf`: retained original audio for retry.

Inference is on-device. Initial Apple speech/Intelligence downloads require connectivity. The app has no cloud backend or analytics. Audio is retained until you delete its meeting; it is not separately encrypted by this app. **Show storage folder** opens the library folder in Finder, and **… → Show meeting folder** opens the selected meeting's files. Deleting a meeting does not remove previously exported Markdown copies. Tell meeting participants when recording.

## Current limits

- Post-meeting transcription only; no speaker identification or mixed-language auto-detection.
- A selected language applies to one entire meeting.
- Long meetings produce summaries in sequential sections, using bounded input chunks and fresh model sessions. This avoids truncating the meeting to fit a small context window; facts spanning chunk boundaries may lose context.
- Missing model, unsupported language, or summary failures leave the transcript/audio available for retry. A crash leaves a recoverable meeting entry and any audio successfully written.
- Transcription accuracy and summary factuality need review. Overlapping speech and speakerphone echo can reduce quality.
- No automatic audio deletion or audio playback UI yet.

## Validation

```sh
swift test
bash scripts/build-app.sh
```

`swift test` requires Xcode's XCTest framework. On a Mac with only Command Line Tools, `bash scripts/check-core.sh` runs the same persistence, export, and multilingual chunking checks without XCTest.

Manual acceptance checks (require a person granting macOS permissions):

- Record and stop a short microphone meeting in each language; inspect transcript and summary.
- With headphones, capture an online call and confirm both local and remote speech, including delayed remote speech, appears in time order.
- Deny microphone/system capture permission and confirm a useful error; retry after enabling it.
- Disable Apple Intelligence and confirm transcription is retained; enable it and retry just the summary.
- Close the window, trigger the shortcut from another app, and reopen from the menu bar.
- Relaunch and confirm saved meetings and exported Markdown remain readable.

Apple references: [SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/), [Foundation Models](https://developer.apple.com/documentation/foundationmodels), [ScreenCaptureKit audio](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/capturesaudio).
