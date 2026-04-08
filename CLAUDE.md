# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

**Clover** — macOS ネイティブのリアルタイム文字起こしアプリ。Apple の Speech フレームワーク（`SpeechTranscriber` / `SpeechAnalyzer`）を使用し、マイク音声とシステム音声（ScreenCaptureKit 経由）を同時にキャプチャ・文字起こしできる。Swift 6.2 / SwiftUI / macOS 26 以降対象。

## ビルド・実行

```bash
# デバッグビルド（レガシーキーチェーンにフォールバック）
swift build
swift run

# デバッグビルド + エンタイトルメント付き署名（Data Protection Keychain + Touch ID 有効）
./scripts/run-dev.sh

# リリースビルド → .app バンドル作成（エンタイトルメント付きコード署名）
./scripts/build-app.sh

# 生成された .app を実行
open Clover.app
```

Swift Package Manager プロジェクト。Xcode プロジェクトファイルは無い。唯一の外部依存は GRDB.swift（SQLite ORM）。

> **Note:** `swift run` は未署名バイナリのため Data Protection Keychain が使えず、レガシーキーチェーンに自動フォールバックする。Touch ID 保護を含む完全な動作確認には `./scripts/run-dev.sh` を使用すること。

## アーキテクチャ

### データフロー（録音時）

```
AudioCaptureManager (マイク/AVAudioEngine)
SystemAudioCaptureManager (システム音声/ScreenCaptureKit)
    ↓ onAudioBuffer コールバック
AudioBufferBridge (AsyncStream<AnalyzerInput> に変換)
    ↓
SpeechTranscriberService (SpeechAnalyzer + SpeechTranscriber)
    ↓ results AsyncSequence
TranscriptStore (@MainActor, @Published segments)
    ↓ Combine .debounce
TranscriptPersistenceService → GRDB/SQLite
```

- **パイプライン**: 音声ソース（mic / system）ごとに独立した `(SpeechTranscriberService, AudioBufferBridge)` ペアを構築。`CaptionViewModel.pipelines` 配列で管理。
- **未確定セグメント**: `TranscriptStore.replaceUnconfirmedSegments` で 200ms スロットル。ソースラベル（`speakerLabel`）ごとに独立管理。

### データ永続化

- SQLite DB: `~/Library/Application Support/Clover/clover.sqlite`（`AppDatabaseManager`）
- テーブル: `vaults`（保管庫）、`projects`（プロジェクト、vaultId で保管庫に紐付き）、`transcripts`（セッション）、`segments`（発話区間）
- プロジェクト = ファイルシステム上のフォルダ（保管庫ディレクトリ配下）
- 保管庫は DB の `vaults` テーブルで管理。初回起動時は `VaultPickerView` で登録
- ID は UUID v7（`UUID.v7()` — 時系列ソート可能）

### MVVM 構成

- **ViewModels**: `CaptionViewModel`（録音制御・文字起こし全体）、`SidebarViewModel`（プロジェクト・文字起こし一覧）
- **Views**: `ContentView`（NavigationSplitView）→ `SidebarView` + `ControlPanelView`
- **Models**: `TranscriptStore`（セグメント一元管理）、`TranscriptSegment`（発話区間）、`VaultRecord`（保管庫）、`AppSettings`（UserDefaults ラッパー + 保管庫ランタイム状態）

### 設定

- `AppSettings` が `@AppStorage` で UserDefaults に永続化
- 認識言語ロケール、表示言語フィルタ
- 保管庫は `AppSettings.currentVault`（ランタイム状態、DB から読み込み）

### 必要な権限（Info.plist）

- `NSMicrophoneUsageDescription` — マイク
- `NSScreenCaptureUsageDescription` — システム音声キャプチャ（画面収録権限）
- `NSSpeechRecognitionUsageDescription` — 音声認識

## コード規約

- UI 文字列は日本語
- `@MainActor` を積極的に使用（ViewModel, Store, Repository）
- `@unchecked Sendable` は ScreenCaptureKit のデリゲート実装など最小限に限定
- `@preconcurrency import` で Apple フレームワークの Sendable 警告を抑制
