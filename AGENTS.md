# CLAUDE.md

## Project Overview

**Dahlia** — macOS native real-time transcription app. Captures microphone audio (AVAudioEngine) and system audio (ScreenCaptureKit) simultaneously, transcribes via Apple Speech framework (`SpeechAnalyzer`/`SpeechTranscriber`), and optionally generates LLM-powered summaries.

Swift 6.2 / SwiftUI / macOS 26+ / Swift Package Manager (no Xcode project). Single external dependency: GRDB.swift (SQLite ORM).

## Build & Run

```bash
swift build && swift run            # Debug (unsigned, legacy keychain fallback)
./scripts/run-dev.sh                # Debug + codesigned (Data Protection Keychain + Touch ID)
./scripts/build-app.sh && open Dahlia.app  # Release .app bundle
./scripts/lint.sh                   # SwiftFormat + SwiftLint
```

> `swift run` cannot use Data Protection Keychain (unsigned). Use `run-dev.sh` for full functionality.

## Architecture

### Recording Data Flow

```
AudioCaptureManager (mic/AVAudioEngine)
SystemAudioCaptureManager (system audio/ScreenCaptureKit)
    ↓ onAudioBuffer callback
AudioBufferBridge → AsyncStream<AnalyzerInput>
    ↓
SpeechTranscriberService (actor, per audio source)
    ↓ results AsyncSequence
TranscriptStore (@MainActor, 200ms throttle per speakerLabel)
    ↓ Combine .debounce(500ms)
TranscriptPersistenceService → GRDB/SQLite
```

Each audio source gets an independent `(SpeechTranscriberService, AudioBufferBridge)` pipeline, managed via `CaptionViewModel.pipelines`.

### Key Components

| Layer | Components |
|-------|-----------|
| **Audio** | `AudioCaptureManager`, `SystemAudioCaptureManager`, `AudioBufferBridge` |
| **Speech** | `SpeechTranscriberService` (actor) |
| **Storage** | `TranscriptStore`, `TranscriptPersistenceService`, `TranscriptionRepository`, `AppDatabaseManager` |
| **LLM** | `LLMService` (OpenAI-compatible API), `SummaryService` (multimodal summaries with `SummaryResult` structured output) |
| **Services** | `VaultSyncService` (FSEvents), `MeetingDetectionService` (3-layer), `KeychainService`, `FolderProjectService` |
| **ViewModels** | `CaptionViewModel` (recording control), `SidebarViewModel` (project/transcript tree, GRDB ValueObservation) |
| **Views** | `ContentView` (NavigationSplitView) → `SidebarView` + `ControlPanelView` + `SettingsView` |

### Database

SQLite at `~/Library/Application Support/Dahlia/dahlia.sqlite`. Tables: `vaults`, `projects` (vault-scoped, path-based), `transcripts`, `segments`, `notes`, `screenshots`. All IDs are UUID v7.

Projects map to filesystem folders under a vault directory. `VaultSyncService` monitors via FSEvents and syncs to DB.

## Code Conventions

- **Concurrency**: `@MainActor` on ViewModels, Store, Repository. `actor` for `SpeechTranscriberService`. `@unchecked Sendable` only for ScreenCaptureKit delegates. `@preconcurrency import` to suppress Apple framework Sendable warnings.
- **DB migrations**: リリース向けのマイグレーションでは既存ユーザーデータを保持すること。`eraseDatabaseOnSchemaChange` のような破壊的リセットは使わず、GRDB の前方互換な追加マイグレーションで対応する。
- **UI strings**: Japanese (primary) + English via `L10n` dynamic localization.
- **Formatting**: SwiftFormat + SwiftLint enforced (see `.swiftformat`, `.swiftlint.yml`). 4-space indent, 150 char line limit, trailing commas required.
- **IDs**: UUID v7 (`UUID.v7()`) for time-sortable ordering.
