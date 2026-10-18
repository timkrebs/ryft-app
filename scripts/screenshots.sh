#!/bin/sh
# Builds the app, runs it in the simulator with mock data and captures one
# screenshot per tab (dark and light) into docs/screenshots/.
#
#   scripts/screenshots.sh ["iPhone 17 Pro"] [tab ...]
set -eu
cd "$(dirname "$0")/.."

DEVICE=${1:-"iPhone 17 Pro"}
shift 2>/dev/null || true
TABS=${*:-"today sleep strain insights profile"}
BUNDLE=dev.timkrebs.ryft
DD=.build/DerivedData
OUT=docs/screenshots

# Names can repeat across runtimes; pin the first available match by UDID.
UDID=$(xcrun simctl list devices available | grep -E "^ +$DEVICE \(" | head -1 \
  | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -n "$UDID" ] || { echo "No simulator named $DEVICE" >&2; exit 1; }
DEVICE=$UDID

xcodegen generate >/dev/null
xcodebuild -scheme Ryft -destination "platform=iOS Simulator,id=$DEVICE" \
  -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO build >/dev/null
APP="$DD/Build/Products/Debug-iphonesimulator/Ryft.app"

xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b >/dev/null
# Clean status bar like the board (9:41, full battery).
xcrun simctl status_bar "$DEVICE" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 >/dev/null 2>&1 || true
xcrun simctl install "$DEVICE" "$APP"
mkdir -p "$OUT"

for scheme in dark light; do
  for tab in $TABS; do
    xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
    xcrun simctl launch "$DEVICE" "$BUNDLE" -demoMode YES -RyftTab "$tab" -appearance "$scheme" >/dev/null
    sleep "${SHOT_DELAY:-3}"
    xcrun simctl io "$DEVICE" screenshot --type=png "$OUT/$tab-$scheme.png" >/dev/null 2>&1
    echo "$OUT/$tab-$scheme.png"
  done
done
