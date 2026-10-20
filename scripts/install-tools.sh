#!/bin/sh
# Pinned lint tools (docs/CI.md → Style): exact release binaries, verified by
# SHA-256, installed to .build/tools. CI and `make style` use the same ones, so a
# Homebrew upgrade never changes what the check means. To update: change the
# version, run this with the new checksum printed by `shasum -a 256`, commit.
set -eu
SWIFTFORMAT_VERSION=0.64.0
SWIFTFORMAT_SHA256=95ea62625d0b898a7af870293311ae6f09e4a3147ecd900593687e4b9ab2fd98
SWIFTLINT_VERSION=0.65.1
SWIFTLINT_SHA256=c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0

dir=.build/tools
mkdir -p "$dir"

fetch() { # name version url sha
  if [ -x "$dir/$1" ] && [ "$("$dir/$1" --version 2>/dev/null || "$dir/$1" version)" = "$2" ]; then return; fi
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/tool.zip" "$3"
  echo "$4  $tmp/tool.zip" | shasum -a 256 -c - >/dev/null || { echo "checksum mismatch for $1 $2" >&2; exit 1; }
  unzip -qo "$tmp/tool.zip" -d "$tmp"
  mv "$tmp/$1" "$dir/$1"
  chmod +x "$dir/$1"
  rm -rf "$tmp"
}

fetch swiftformat "$SWIFTFORMAT_VERSION" \
  "https://github.com/nicklockwood/SwiftFormat/releases/download/$SWIFTFORMAT_VERSION/swiftformat.zip" "$SWIFTFORMAT_SHA256"
fetch swiftlint "$SWIFTLINT_VERSION" \
  "https://github.com/realm/SwiftLint/releases/download/$SWIFTLINT_VERSION/portable_swiftlint.zip" "$SWIFTLINT_SHA256"
echo "tools: swiftformat $("$dir/swiftformat" --version), swiftlint $("$dir/swiftlint" version)"
