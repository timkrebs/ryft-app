#!/bin/sh
# Prints an xcodebuild destination for CI: a simulator of its own, created fresh on the
# newest iOS runtime that has $SIMULATOR's device type (default iPhone 17 Pro). Only if
# no runtime has it: the newest runtime and its first iPhone. A fresh device has no paired
# Apple Watch. Parallel testing clones the device, and cloning a paired one needs the
# watchOS runtime, which some runner images lack ("Failed to clone device … The watchOS
# 27.0 simulator runtime is not available").
#
# "Newest runtime" alone isn't enough: iOS 27.1 (24A94425) supports only "iPhone Duo",
# whose wide layout turns the tab bar into a side strip, and the UI tests ran on it
# without anyone choosing it (2026-10-22).
set -eu
want="${SIMULATOR:-iPhone 17 Pro}"
pick=$(xcrun simctl list -j devicetypes runtimes | python3 -c '
import json, sys
want = sys.argv[1]
data = json.load(sys.stdin)
runtimes = [r for r in data["runtimes"] if r.get("platform") == "iOS" and r.get("isAvailable")]
if not runtimes:
    sys.exit("No iOS simulator runtime available")
def iphones(r):
    return [d for d in r.get("supportedDeviceTypes", []) if d.get("productFamily") == "iPhone"]
newest_first = sorted(runtimes, key=lambda r: [int(p) for p in r["version"].split(".")], reverse=True)
match = next(((r, d) for r in newest_first for d in iphones(r) if d["name"] == want), None)
if match is None:
    runtime = next((r for r in newest_first if iphones(r)), None)
    if runtime is None:
        sys.exit("No iPhone device type on any iOS runtime")
    match = (runtime, iphones(runtime)[0])
    print("ci-simulator: %s not available; using %s" % (want, match[1]["name"]), file=sys.stderr)
runtime, device = match
print("ci-simulator: %s on iOS %s (%s)" % (device["name"], runtime["version"], runtime.get("buildversion", "?")), file=sys.stderr)
print(device["identifier"], runtime["identifier"])
' "$want")
# One per runtime and device type: reused on a machine that runs this again (locally, say).
devtype=${pick% *}
runtime=${pick#* }
udid=$(xcrun simctl list -j devices available | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"].get(sys.argv[1], [])
print(next((d["udid"] for d in devices if d["name"] == "RYFT CI" and d.get("deviceTypeIdentifier") == sys.argv[2]), ""))
' "$runtime" "$devtype")
[ -n "$udid" ] || udid=$(xcrun simctl create "RYFT CI" $pick)
echo "platform=iOS Simulator,id=$udid"
