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
# A device of its own for every job, never reused: the persistent "RYFT CI" device passed
# its first job and hung the next ones ("test runner hung before establishing connection",
# 2026-10-30, three times). The name is unique per workflow attempt, "RYFT CI <run id>-<attempt>"
# (CI_SIM_NAME overrides it); a leftover of the same name is deleted first.
# ci-simulator-cleanup.sh removes the device and its clones after the job.
name="${CI_SIM_NAME:-RYFT CI ${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}}"
xcrun simctl list -j devices | python3 -c '
import json, sys
for devices in json.load(sys.stdin)["devices"].values():
    for d in devices:
        if d["name"] == sys.argv[1]:
            print(d["udid"])
' "$name" | while read -r old; do xcrun simctl delete "$old" || true; done
udid=$(xcrun simctl create "$name" $pick)
echo "platform=iOS Simulator,id=$udid"
