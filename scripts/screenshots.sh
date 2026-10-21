#!/bin/sh
# Builds the app, runs it in the simulator with mock data and captures one
# screenshot per tab (dark and light) into docs/screenshots/. Screens demo mode
# never reaches (the onboarding steps, Profile → Sign-in methods) are opened
# directly with the Debug launch argument `-RyftScreen` (RyftApp → DebugScreen).
#
#   scripts/screenshots.sh ["iPhone 17 Pro"] [tab, screen or scenario ...]
#   screens: invite consent aboutYou aboutYouSaved accountHint signInMethods syncDetails baselineSleepNeed sleepNeed bedtime tonight
#   scenarios (Today in one in-between state, `-RyftScenario`): import pending calibrating watch
#   SHOT_LANG=de: German (files end in -de)
set -eu
cd "$(dirname "$0")/.."

DEVICE=${1:-"iPhone 17 Pro"}
shift 2>/dev/null || true
TABS=${*:-"today sleep strain insights profile"}
BUNDLE=dev.timkrebs.ryft
DD=build/DerivedData   # shared with make build / make strings
OUT=docs/screenshots

# Names can repeat across runtimes; pin the first available match by UDID.
UDID=$(xcrun simctl list devices available | grep -E "^ +$DEVICE \(" | head -1 \
  | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -n "$UDID" ] || { echo "No simulator named $DEVICE" >&2; exit 1; }
DEVICE=$UDID

for c in Debug Release; do [ -f "Config/$c.xcconfig" ] || cp "Config/$c.xcconfig.example" "Config/$c.xcconfig"; done
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

LANG_SHOT=${SHOT_LANG:-}
for scheme in dark light; do
  for tab in $TABS; do
    xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
    case $tab in
      invite|consent|aboutYou|aboutYouSaved|accountHint|signInMethods|syncDetails|baselineSleepNeed|sleepNeed|bedtime|tonight) set -- -RyftScreen "$tab" ;;
      import|pending|calibrating|watch) set -- -RyftTab today -RyftScenario "$tab" ;;
      *) set -- -RyftTab "$tab" ;;
    esac
    name="$tab-$scheme"
    if [ -n "$LANG_SHOT" ]; then
      set -- "$@" -AppleLanguages "($LANG_SHOT)" -AppleLocale "$LANG_SHOT"
      name="$name-$LANG_SHOT"
    fi
    xcrun simctl launch "$DEVICE" "$BUNDLE" -demoMode YES "$@" -appearance "$scheme" >/dev/null
    sleep "${SHOT_DELAY:-3}"
    xcrun simctl io "$DEVICE" screenshot --type=png "$OUT/$name.png" >/dev/null 2>&1
    echo "$OUT/$name.png"
  done
done
