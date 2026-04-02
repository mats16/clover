#!/bin/bash
set -euo pipefail

APP_NAME="Transcriber"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "=== Building ${APP_NAME} ==="
swift build -c release

# .app バンドル作成
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"

rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS}"
mkdir -p "${CONTENTS}/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${MACOS}/${APP_NAME}"
cp "Resources/Info.plist" "${CONTENTS}/Info.plist"

# コード署名
codesign --force --sign - "${APP_BUNDLE}"

echo "=== Build complete: ${APP_BUNDLE} ==="
