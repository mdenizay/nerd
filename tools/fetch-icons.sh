#!/bin/bash
# Downloads the Lucide icons Nerd uses (ISC licence, https://lucide.dev) into
# Resources/Assets.xcassets as template vector images.
# Usage: tools/fetch-icons.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="0.460.0"
ASSETS="$ROOT/Resources/Assets.xcassets"
ICONS=(server layout-grid globe square-plus code-xml hexagon hash database mail list-checks settings
       leaf triangle sparkles file zap atom layers wind package file-text layout-dashboard waypoints flame
       terminal folder play square lock send refresh-cw ellipsis arrow-up-right plus link search trash-2
       network memory-stick activity hard-drive triangle-alert circle-alert arrow-left-right check box power
       app-window table circle-arrow-down bug plug cpu scroll-text circle-pause eraser copy)
mkdir -p "$ASSETS/Icons"
printf '{ "info" : { "author" : "xcode", "version" : 1 } }\n' > "$ASSETS/Contents.json"
printf '{ "info" : { "author" : "xcode", "version" : 1 }, "properties" : { "provides-namespace" : true } }\n' > "$ASSETS/Icons/Contents.json"
for name in "${ICONS[@]}"; do
    dir="$ASSETS/Icons/$name.imageset"
    mkdir -p "$dir"
    curl -fsSL "https://unpkg.com/lucide-static@$VERSION/icons/$name.svg" \
        | sed -e 's/currentColor/#000000/g' -e 's/stroke-width="2"/stroke-width="1.75"/' > "$dir/$name.svg"
    cat > "$dir/Contents.json" <<JSON
{
  "images" : [ { "filename" : "$name.svg", "idiom" : "universal" } ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "preserves-vector-representation" : true, "template-rendering-intent" : "template" }
}
JSON
done
curl -fsSL "https://unpkg.com/lucide-static@$VERSION/LICENSE" -o "$ASSETS/Icons/LICENSE-lucide.txt" || true
echo "Fetched ${#ICONS[@]} icons"
