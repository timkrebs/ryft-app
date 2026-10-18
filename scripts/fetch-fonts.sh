#!/bin/sh
# Downloads Satoshi from Fontshare (ITF Free Font License) into Ryft/Resources/Fonts/.
# The fonts are free to embed in the app but must not be redistributed through a
# repository, so they are git-ignored. Without them the app falls back to SF Pro Rounded.
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/satoshi.zip" "https://api.fontshare.com/v2/fonts/download/satoshi"
unzip -q "$tmp/satoshi.zip" -d "$tmp"
mkdir -p Ryft/Resources/Fonts
for w in Regular Medium Bold; do
  cp "$(find "$tmp" -name "Satoshi-$w.otf" | head -1)" Ryft/Resources/Fonts/
done
echo "Satoshi installed in Ryft/Resources/Fonts. Re-run xcodegen generate."
