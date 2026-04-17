#!/bin/bash
# Shared shell functions for build-app.sh and run-dev.sh.

reverse_client_id() {
    printf '%s' "$1" | awk -F. '{for (i = NF; i > 0; i--) printf "%s%s", $i, (i > 1 ? "." : "")}'
}

configure_google_signin_plist() {
    local plist_path="$1"

    /usr/libexec/PlistBuddy -c "Delete :GIDClientID" "$plist_path" >/dev/null 2>&1 || true
    /usr/libexec/PlistBuddy -c "Delete :GOOGLE_CLIENT_SECRET" "$plist_path" >/dev/null 2>&1 || true
    /usr/libexec/PlistBuddy -c "Delete :CFBundleURLTypes" "$plist_path" >/dev/null 2>&1 || true

    if [ -n "${GOOGLE_CLIENT_ID:-}" ]; then
        local reversed_client_id
        reversed_client_id="$(reverse_client_id "$GOOGLE_CLIENT_ID")"

        /usr/libexec/PlistBuddy -c "Add :GIDClientID string ${GOOGLE_CLIENT_ID}" "$plist_path"
        /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes array" "$plist_path"
        /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0 dict" "$plist_path"
        /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLName string GoogleSignIn" "$plist_path"
        /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "$plist_path"
        /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string ${reversed_client_id}" "$plist_path"
    fi

    if [ -n "${GOOGLE_CLIENT_SECRET:-}" ]; then
        /usr/libexec/PlistBuddy -c "Add :GOOGLE_CLIENT_SECRET string ${GOOGLE_CLIENT_SECRET}" "$plist_path"
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

    codesign --force --sign "$SIGN_IDENTITY" "$@" "$path"
}
