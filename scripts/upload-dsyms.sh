#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ $# -lt 1 ]; then
    echo "usage: $0 <build-dir> [app-name]" >&2
    exit 1
fi

BUILD_DIR="$1"
APP_NAME="${2:-Dahlia}"
DSYM_PATH="${BUILD_DIR}/${APP_NAME}.dSYM"
SENTRY_ORG="${SENTRY_ORG:-dahlia-ez}"
SENTRY_PROJECT="${SENTRY_PROJECT:-dahlia-app}"

cd "$PROJECT_DIR"

if [ -z "${SENTRY_AUTH_TOKEN:-}" ]; then
    echo "=== Skipping Sentry dSYM upload: SENTRY_AUTH_TOKEN is not set ==="
    exit 0
fi

if ! command -v sentry-cli >/dev/null 2>&1; then
    echo "=== Skipping Sentry dSYM upload: sentry-cli not found ==="
    exit 0
fi

if [ ! -d "$DSYM_PATH" ]; then
    echo "=== Skipping Sentry dSYM upload: ${DSYM_PATH} not found ==="
    exit 0
fi

echo "=== Uploading dSYM to Sentry (${SENTRY_ORG}/${SENTRY_PROJECT}) ==="
sentry-cli debug-files upload \
    --org "$SENTRY_ORG" \
    --project "$SENTRY_PROJECT" \
    --include-sources \
    "$DSYM_PATH"
