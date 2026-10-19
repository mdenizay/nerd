#!/bin/zsh
# Builds build/Nerd.app. Release builds are universal (Apple silicon + Intel).
# With a Developer ID certificate in the keychain the app is signed for
# distribution (hardened runtime, as notarization requires); otherwise ad hoc.
# Usage: scripts/build-app.sh [release|debug]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CONFIG=${1:-release}
APP="$ROOT/build/Nerd.app"

if [ "$CONFIG" = release ]; then
    ARCHS=(--arch arm64 --arch x86_64)
else
    ARCHS=()
fi
swift build -c "$CONFIG" "${ARCHS[@]}"
BIN="$(swift build -c "$CONFIG" "${ARCHS[@]}" --show-bin-path)/Nerd"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Nerd"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
if [ "$CONFIG" = release ] && [ -n "$IDENTITY" ]; then
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi
# Keep the build copy out of Spotlight / Launchpad; only /Applications counts.
touch "$ROOT/build/.metadata_never_index"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP" 2>/dev/null || true
echo "Built $APP"
