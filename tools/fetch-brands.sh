#!/bin/bash
# Downloads technology logos from Simple Icons (https://simpleicons.org) into
# Resources/Assets.xcassets/Brands as template vector images. Nerd tints them
# with each brand's colour (see Icons.brandColors).
# Vue's logo is CC-BY-NC-SA and is left out on purpose; see NOTICE.md.
# Usage: tools/fetch-brands.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="13.21.0"
DIR="$ROOT/Resources/Assets.xcassets/Brands"
SLUGS=(laravel livewire inertia react svelte nextdotjs astro dotnet blazor php nodedotjs
       mysql mariadb postgresql redis meilisearch minio docker caddy composer)
mkdir -p "$DIR"
printf '{ "info" : { "author" : "xcode", "version" : 1 }, "properties" : { "provides-namespace" : true } }\n' > "$DIR/Contents.json"
for slug in "${SLUGS[@]}"; do
    set="$DIR/$slug.imageset"
    mkdir -p "$set"
    curl -fsSL "https://cdn.jsdelivr.net/npm/simple-icons@$VERSION/icons/$slug.svg" -o "$set/$slug.svg"
    cat > "$set/Contents.json" <<JSON
{
  "images" : [ { "filename" : "$slug.svg", "idiom" : "universal" } ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "preserves-vector-representation" : true, "template-rendering-intent" : "template" }
}
JSON
done
echo "Fetched ${#SLUGS[@]} logos"
