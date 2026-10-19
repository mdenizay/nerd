#!/bin/zsh
# Collects every localizable string from the sources into
# Resources/Localizable.xcstrings (source language: Turkish). Add the English
# value for new keys afterwards, in Xcode or by editing the JSON.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="$(mktemp -d)"
touch Sources/Nerd/**/*.swift
swift build -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$OUT"
xcrun xcstringstool sync Resources/Localizable.xcstrings --stringsdata "$OUT"/*.stringsdata
rm -rf "$OUT"
echo "Synced Resources/Localizable.xcstrings"
