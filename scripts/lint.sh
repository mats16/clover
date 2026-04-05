#!/bin/bash
# SwiftFormat + SwiftLint を実行するスクリプト
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=== SwiftFormat ==="
if command -v swiftformat &>/dev/null; then
    swiftformat Sources/
    echo "SwiftFormat: done"
else
    echo "SwiftFormat not found. Install: brew install swiftformat"
    exit 1
fi

echo ""
echo "=== SwiftLint ==="
if command -v swiftlint &>/dev/null; then
    swiftlint lint --quiet || true
    echo "SwiftLint: done"
else
    echo "SwiftLint not found (requires Xcode.app). Skipping."
fi
