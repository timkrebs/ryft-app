#!/bin/sh
# Prints an xcodebuild destination for CI: $SIMULATOR if this Xcode has it
# (default "iPhone 17 Pro", as in the Makefile), otherwise the newest available iPhone.
set -eu
want="${SIMULATOR:-iPhone 17 Pro}"
xcrun simctl list devices available -j | python3 -c '
import json, sys
want = sys.argv[1]
devices = [d for runtime, ds in json.load(sys.stdin)["devices"].items() if "iOS" in runtime for d in ds]
iphones = [d for d in devices if d["name"].startswith("iPhone")]
pick = next((d for d in iphones if d["name"] == want), iphones[-1] if iphones else None)
if pick is None:
    sys.exit("No iPhone simulator available")
print("platform=iOS Simulator,id=" + pick["udid"])
' "$want"
