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

# Icons (Lucide), technology logos, the brand accent colour and the app icon
# The app icon is a layered Icon Composer file: Liquid Glass on macOS 26, and
# actool renders AppIcon.icns from it for earlier versions.
xcrun actool "$ROOT/Resources/Assets.xcassets" "$ROOT/Resources/AppIcon.icon" --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 15.0 --app-icon AppIcon \
    --output-partial-info-plist "$ROOT/build/assets-info.plist" >/dev/null

# Translations: the catalog's source language is Turkish, so tr.lproj only has
# to exist; English comes from the compiled catalog.
xcrun xcstringstool compile "$ROOT/Resources/Localizable.xcstrings" --output-directory "$APP/Contents/Resources"
mkdir -p "$APP/Contents/Resources/tr.lproj"
echo '/* Turkish is the source language. */' > "$APP/Contents/Resources/tr.lproj/Localizable.strings"

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
