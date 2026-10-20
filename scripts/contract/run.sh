#!/bin/sh
# Contract check: the platform's API.md examples decode with the app's models.
#   scripts/contract/run.sh [path/to/API.md]   (default ../plattform/docs/API.md)
set -eu
api="${1:-../plattform/docs/API.md}"
out="${TMPDIR:-/tmp}/ryft-contract"
rm -rf "$out" && mkdir -p "$out"
python3 scripts/contract/extract.py "$api" "$out/examples"
xcrun swiftc -swift-version 5 -O -o "$out/contract" \
  Ryft/Networking/Models.swift Ryft/Networking/SleepMath.swift Ryft/App/Formatting.swift \
  scripts/contract/main.swift
"$out/contract" "$out/examples"
