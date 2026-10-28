#!/bin/sh
# Exports the PNG attachments of the import screenshot suite (`make ui-shots`) from .xcresult bundles.
#
#   scripts/export-ui-shots.sh OUT_DIR BUNDLE.xcresult [BUNDLE.xcresult ...]
#
# `xcresulttool export attachments` writes files named by UUID and a manifest.json; each PNG is copied to
# OUT_DIR/<attachment name>.png, the name the test gave it (screen, state, language, scheme, text size). Needs jq
# (/usr/bin/jq on macOS).
set -eu

if [ "$#" -lt 2 ]; then
    echo "usage: $0 OUT_DIR BUNDLE.xcresult [BUNDLE.xcresult ...]" >&2
    exit 2
fi
out=$1
shift
mkdir -p "$out"
raw=$(mktemp -d)
trap 'rm -rf "$raw"' EXIT

total=0
for bundle in "$@"; do
    rm -rf "$raw/export"
    xcrun xcresulttool export attachments --path "$bundle" --output-path "$raw/export" >/dev/null
    # "<name>_<repetition>_<uuid>.png" is the suggested file name; the test's own name is what stands before the suffix.
    jq -r '.[].attachments[] | select(.suggestedHumanReadableName | endswith(".png"))
           | [.exportedFileName, (.suggestedHumanReadableName | sub("(_[0-9]+_[0-9A-Fa-f-]{36})?\\.png$"; ""))] | @tsv' \
        "$raw/export/manifest.json" |
        while IFS="$(printf '\t')" read -r file name; do
            # Two shots with one name (e.g. a language that didn't apply) would overwrite each other silently.
            if [ -e "$out/$name.png" ]; then
                echo "duplicate screenshot name: $name (from $bundle)" >&2
                exit 1
            fi
            cp "$raw/export/$file" "$out/$name.png"
        done
    count=$(jq '[.[].attachments[] | select(.suggestedHumanReadableName | endswith(".png"))] | length' "$raw/export/manifest.json")
    echo "$bundle: $count screenshots"
    total=$((total + count))
done
[ "$total" -gt 0 ]
