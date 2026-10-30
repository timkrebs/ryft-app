#!/bin/sh
# After a CI job (ios.yml, `if: always()`): shuts down and deletes the job's simulator and
# the clones parallel testing made of it, then sweeps "RYFT CI*" devices that a crashed job
# left behind (unused for over a day). Same name rule as ci-simulator.sh.
#
# Clones live in a second device set, ~/Library/Developer/XCTestDevices, named
# "Clone <n> of <source name>". On 2026-10-30 that set held 277 of them (since 2026-10-21),
# nothing ever deleted them. Only devices named after our own are touched.
# Never fails the job.
set -u
name="${CI_SIM_NAME:-RYFT CI ${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}}"
sets="$HOME/Library/Developer/CoreSimulator/Devices $HOME/Library/Developer/XCTestDevices"
prefix="${CI_SIM_PREFIX:-RYFT CI}"   # overridden only to test this script
max_age_days="${CI_SIM_MAX_AGE_DAYS:-1}"

# Prints "<set path> <udid>" for the devices to remove: the job's own and its clones, and
# every "RYFT CI*" device (or clone of one) whose data directory is older than max_age_days.
doomed() {
  for set in $sets; do
    [ -d "$set" ] || continue
    xcrun simctl --set "$set" list -j devices | python3 -c '
import json, os, sys, time
set_path, name, max_age, prefix = sys.argv[1], sys.argv[2], float(sys.argv[3]), sys.argv[4]
for devices in json.load(sys.stdin)["devices"].values():
    for d in devices:
        n = d["name"]
        base = n.split(" of ", 1)[1] if n.startswith("Clone ") and " of " in n else n
        mine = base == name
        ours = base.startswith(prefix)
        if not (mine or ours):
            continue
        try:
            age = (time.time() - os.stat(os.path.join(set_path, d["udid"])).st_mtime) / 86400
        except OSError:
            age = max_age + 1   # no data directory: broken, remove
        if mine or age > max_age:
            print(set_path, d["udid"], n)
' "$set" "$name" "$max_age_days" "$prefix"
  done
}

doomed | while read -r set udid dname; do
  echo "ci-simulator-cleanup: deleting $dname ($udid)"
  xcrun simctl --set "$set" shutdown "$udid" 2>/dev/null || true
  xcrun simctl --set "$set" delete "$udid" || true
done
exit 0
