# Repository Guidelines

## Project Structure & Module Organization

Transcripted is an on-device macOS meeting notebook with no third-party dependencies. `Package.swift` defines one executable and one test target. Source files live in `Sources/Transcripted/`: `TranscriptedApp.swift` contains the SwiftUI interface, `AppModel.swift` coordinates workflows, `Recorder.swift` captures audio, `Intelligence.swift` handles transcription and summaries, `Meeting.swift` defines persistence and export, and `HotKey.swift` manages the global shortcut.

Tests live in `Tests/TranscriptedTests/`. Bundle metadata and permission descriptions belong in `Resources/Info.plist`; build and validation scripts live in `scripts/`. Generated outputs use `.build/` and `dist/`.

## Build, Test, and Development Commands

Use an Apple Silicon Mac with macOS 26+, Swift 6.2+, and a macOS 26+ SDK. Summaries require Apple Intelligence enabled with its model downloaded.

- `swift build`: compile the executable for development.
- `bash scripts/build-app.sh`: build the ARM64 release app and sign it locally; optionally set `SIGNING_IDENTITY` to an installed certificate.
- `open dist/Transcripted.app`: launch the bundled app so macOS associates privacy permissions correctly.
- `swift test`: run XCTest checks; requires Xcode's XCTest framework.
- `bash scripts/check-core.sh`: run shared core checks without XCTest on Command Line Tools installations.

## Coding Style & Naming Conventions

Follow existing Swift style: four-space indentation, `UpperCamelCase` types, and `lowerCamelCase` properties and functions. Name files after their principal type or responsibility. The package uses Swift 5 language mode with Swift 6.2 tooling. Preserve existing actor isolation and asynchronous workflow boundaries. No formatter or linter is configured; keep formatting consistent with neighboring code.

## Testing Guidelines

Use descriptive `test...` methods in `MeetingTests`. Shared `check...` functions support both XCTest and the `CORE_CHECK` executable. Test persistence using temporary directories with cleanup. Cover export, multilingual chunking, editing, and deletion when changing those behaviors; no coverage percentage is configured.

For capture or UI changes, build the app and perform relevant README acceptance checks, including permission denial, retries, shortcuts, and relaunch persistence.

## Commit & Pull Request Guidelines

Git history is unavailable in this checkout. Use concise, imperative commit subjects describing a focused change. PRs should explain behavior changes, list validation performed, link relevant issues, and include screenshots for UI changes. Note manual checks that remain unperformed.

## Privacy & Storage

Keep recordings and transcripts out of commits and test fixtures. Production meetings reside in `~/Library/Application Support/Transcripted/Meetings/<id>/`; use temporary storage for tests. Preserve on-device processing and recoverable audio/transcripts when handling failures.
