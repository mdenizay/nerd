#!/bin/bash
# Builds Nerd, notarizes it, publishes a GitHub release and updates the Homebrew
# cask in mdenizay/homebrew-tap. Needs `gh auth login`, a Developer ID
# certificate and notary credentials stored with
#   xcrun notarytool store-credentials <profile> ...
# Usage: NOTARY_PROFILE=<profile> tools/release.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="mdenizay/nerd"
TAP="mdenizay/homebrew-tap"
PROFILE="${NOTARY_PROFILE:-nerd}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
APP="$ROOT/build/Nerd.app"
ZIP="$ROOT/build/Nerd-$VERSION.zip"

"$ROOT/scripts/build-app.sh" release

SIGNATURE="$(codesign -dvv "$APP" 2>&1 || true)"
if [[ "$SIGNATURE" != *"Authority=Developer ID Application"* ]]; then
    echo "Not Developer ID signed; refusing to publish a build Gatekeeper would block." >&2
    exit 1
fi

rm -f "$ZIP"
ditto -c -k --norsrc --noextattr --noqtn --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --norsrc --noextattr --noqtn --keepParent "$APP" "$ZIP"
spctl --assess --type execute "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP" 2>/dev/null || true
SHA="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"

# Release notes: this version's section of the change log.
NOTES="$(mktemp)"
awk -v v="## $VERSION" '$0 == v {on = 1; next} /^## / {on = 0} on' "$ROOT/CHANGELOG.md" > "$NOTES"
gh release create "v$VERSION" "$ZIP" --repo "$REPO" --title "v$VERSION" --notes-file "$NOTES"
rm -f "$NOTES"

WORK="$(mktemp -d)"
gh repo clone "$TAP" "$WORK/tap" -- -q
mkdir -p "$WORK/tap/Casks"
sed -e "s/VERSION/$VERSION/" -e "s/SHA256/$SHA/" "$ROOT/packaging/nerd.rb" | grep -v '^# ' > "$WORK/tap/Casks/nerd.rb"
git -C "$WORK/tap" add Casks/nerd.rb
git -C "$WORK/tap" commit -q -m "nerd $VERSION"
git -C "$WORK/tap" push -q
rm -rf "$WORK"
echo "Released v$VERSION: brew install --cask mdenizay/tap/nerd"
