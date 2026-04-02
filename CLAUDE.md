# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

**Clover** — macOS ネイティブのリアルタイム文字起こしアプリ。Apple の Speech フレームワーク（`SpeechTranscriber` / `SpeechAnalyzer`）を使用し、マイク音声とシステム音声（ScreenCaptureKit 経由）を同時にキャプチャ・文字起こしできる。Swift 6.2 / SwiftUI / macOS 26 以降対象。

## ビルド・実行

```bash
# デバッグビルド
swift build

# リリースビルド → .app バンドル作成（コード署名付き）
./scripts/build-app.sh

# 生成された .app を実行
open Clover.app
```

Swift Package Manager プロジェクト。Xcode プロジェクトファイルは無い。唯一の外部依存は GRDB.swift（SQLite ORM）。

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

- プロジェクト = ファイルシステム上のフォルダ（保管庫ディレクトリ配下）
- 各プロジェクトフォルダ内に `.transcriptions.sqlite` を配置（`ProjectDatabaseManager`）
- スキーマは `ProjectDatabaseManager.migrator` でマイグレーション管理（v1〜v3）
- テーブル: `transcriptions`（セッション）、`segments`（発話区間）
- ID は UUID v7（`UUID.v7()` — 時系列ソート可能）

### MVVM 構成

- **ViewModels**: `CaptionViewModel`（録音制御・文字起こし全体）、`SidebarViewModel`（プロジェクト・文字起こし一覧）
- **Views**: `ContentView`（NavigationSplitView）→ `SidebarView` + `ControlPanelView`
- **Models**: `TranscriptStore`（セグメント一元管理）、`TranscriptSegment`（発話区間）、`FolderProject`（フォルダプロジェクト）、`AppSettings`（UserDefaults ラッパー）

### 設定

- `AppSettings` が `@AppStorage` で UserDefaults に永続化
- 保管庫パス（デフォルト: `~/Documents/Obsidian Vault`）
- 認識言語ロケール、表示言語フィルタ

### 必要な権限（Info.plist）

- `NSMicrophoneUsageDescription` — マイク
- `NSScreenCaptureUsageDescription` — システム音声キャプチャ（画面収録権限）
- `NSSpeechRecognitionUsageDescription` — 音声認識

## コード規約

- UI 文字列は日本語
- `@MainActor` を積極的に使用（ViewModel, Store, Repository）
- `@unchecked Sendable` は ScreenCaptureKit のデリゲート実装など最小限に限定
- `@preconcurrency import` で Apple フレームワークの Sendable 警告を抑制
