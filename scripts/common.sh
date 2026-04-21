#!/bin/bash
# Shared shell functions for build-app.sh and run-dev.sh.

configure_google_calendar_plist() {
    local plist_path="$1"

    /usr/libexec/PlistBuddy -c "Delete :GIDClientID" "$plist_path" >/dev/null 2>&1 || true
    /usr/libexec/PlistBuddy -c "Delete :GOOGLE_CLIENT_ID" "$plist_path" >/dev/null 2>&1 || true
    /usr/libexec/PlistBuddy -c "Delete :GOOGLE_CLIENT_SECRET" "$plist_path" >/dev/null 2>&1 || true

    if [ -n "${GOOGLE_CLIENT_ID:-}" ]; then
        /usr/libexec/PlistBuddy -c "Add :GOOGLE_CLIENT_ID string ${GOOGLE_CLIENT_ID}" "$plist_path"
    fi

    if [ -n "${GOOGLE_CLIENT_SECRET:-}" ]; then
        /usr/libexec/PlistBuddy -c "Add :GOOGLE_CLIENT_SECRET string ${GOOGLE_CLIENT_SECRET}" "$plist_path"
    fi
}

configure_sentry_plist() {
    local plist_path="$1"

    /usr/libexec/PlistBuddy -c "Delete :SENTRY_DSN" "$plist_path" >/dev/null 2>&1 || true

    if [ -n "${SENTRY_DSN:-}" ]; then
        /usr/libexec/PlistBuddy -c "Add :SENTRY_DSN string ${SENTRY_DSN}" "$plist_path"
    fi
}

has_entitlements() {
    local entitlements_path="$1"

    if [ ! -f "$entitlements_path" ]; then
        return 1
    fi

    plutil -convert xml1 -o - "$entitlements_path" 2>/dev/null | grep -q "<key>"
}

codesign_path() {
    local path="$1"
    shift

    codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$@" "$path"
}
