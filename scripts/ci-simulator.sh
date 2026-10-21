#!/bin/sh
# Prints an xcodebuild destination for CI: a simulator of its own, created fresh on the
# newest iOS runtime ($SIMULATOR's device type, default iPhone 17 Pro, else the newest
# iPhone). A fresh device has no paired Apple Watch. Parallel testing clones the device,
# and cloning a paired one needs the watchOS runtime, which some runner images lack
# ("Failed to clone device … The watchOS 27.0 simulator runtime is not available").
set -eu
want="${SIMULATOR:-iPhone 17 Pro}"
pick=$(xcrun simctl list -j devicetypes runtimes | python3 -c '
import json, sys
want = sys.argv[1]
data = json.load(sys.stdin)
runtimes = [r for r in data["runtimes"] if r.get("platform") == "iOS" and r.get("isAvailable")]
if not runtimes:
    sys.exit("No iOS simulator runtime available")
runtime = max(runtimes, key=lambda r: [int(p) for p in r["version"].split(".")])
iphones = [d for d in runtime.get("supportedDeviceTypes", []) if d.get("productFamily") == "iPhone"]
if not iphones:
    sys.exit("No iPhone device type for " + runtime["name"])
device = next((d for d in iphones if d["name"] == want), iphones[-1])
print(device["identifier"], runtime["identifier"])
' "$want")
# One per runtime: reused on a machine that runs this again (locally, say).
runtime=${pick#* }
udid=$(xcrun simctl list -j devices available | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"].get(sys.argv[1], [])
print(next((d["udid"] for d in devices if d["name"] == "RYFT CI"), ""))
' "$runtime")
[ -n "$udid" ] || udid=$(xcrun simctl create "RYFT CI" $pick)
echo "platform=iOS Simulator,id=$udid"
