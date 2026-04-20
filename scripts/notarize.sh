#!/bin/bash
set -euo pipefail

APP_NAME="Dahlia"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_BUNDLE="${PROJECT_DIR}/${APP_NAME}.app"
ZIP_PATH="${PROJECT_DIR}/${APP_NAME}.zip"
NOTARY_PROFILE="${NOTARY_PROFILE:-dahlia-notary}"

require_command() {
    local command_name="$1"

    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "error: required command not found: ${command_name}" >&2
        exit 1
    fi
}

check_notary_profile() {
    if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        cat >&2 <<EOF
error: notarytool keychain profile '${NOTARY_PROFILE}' is not available.

Create it once with:
  xcrun notarytool store-credentials "${NOTARY_PROFILE}" \\
    --apple-id "YOUR_APPLE_ID" \\
    --team-id "YOUR_TEAM_ID" \\
    --password "APP_SPECIFIC_PASSWORD"
EOF
        exit 1
    fi
}

cd "$PROJECT_DIR"

require_command xcrun
require_command codesign
require_command ditto
require_command spctl

check_notary_profile

echo "=== Building signed app ==="
"${SCRIPT_DIR}/build-app.sh"

echo "=== Verifying signature ==="
codesign -dvvv --entitlements - --xml "$APP_BUNDLE"

echo "=== Creating notarization archive ==="
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "=== Submitting for notarization ==="
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

echo "=== Stapling notarization ticket ==="
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"

echo "=== Verifying Gatekeeper assessment ==="
spctl -a -vvv -t exec "$APP_BUNDLE"

echo "=== Repacking stapled app ==="
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "=== Notarization complete: ${ZIP_PATH} ==="
