#!/bin/bash
set -euo pipefail

APP_NAME="Dahlia"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "=== Building ${APP_NAME} (debug) ==="
swift build

BINARY=".build/debug/${APP_NAME}"

# エンタイトルメント付きで署名（Data Protection Keychain + Touch ID が有効になる）
SIGN_IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Kazuki Matsuda (XCHHYPN52N)}"
codesign --force --sign "$SIGN_IDENTITY" --entitlements "${PROJECT_DIR}/Dahlia.entitlements" "$BINARY"

echo "=== Running ${APP_NAME} ==="
exec "$BINARY"
