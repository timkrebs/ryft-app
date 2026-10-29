#!/bin/sh
# Builds the app, runs it in the simulator with mock data and captures one
# screenshot per tab (dark and light) into docs/screenshots/. Screens demo mode
# never reaches (the onboarding steps, Profile → Sign-in methods) are opened
# directly with the Debug launch argument `-RyftScreen` (RyftApp → DebugScreen).
#
#   scripts/screenshots.sh ["iPhone 17 Pro"] [tab, screen or scenario ...]
#   screens: notifications invite consent aboutYou aboutYouSaved accountHint signInMethods syncDetails baselineSleepNeed sleepNeed bedtime tonight
#            report-problem report-problem-details report-problem-sent report-problem-queued report-problem-rate-limited
#            report-problem-included
#            refresh-details-send
#   scenarios (Today in one in-between state, `-RyftScenario`): import pending calibrating watch
#     waitingForSleep pendingNoPrevious recalculating recalculatingYesterday needsVitals needsVitalsBaselines
#     (Today's rows, ui.md §1.6); nightGap scoringSlow (the night hint and "Taking longer than usual")
#     blockedHRV blockedNoNight blockedOura learningHRV (honest calibration: N1, N2, N1 both signals, S2; design.md §7 rev. 2)
#     learningRestingHR learningRestingHRScored blockedEarly (F3: S1 counting resting HR, S2 with it, N1 early)
#   SHOT_LANG=de: German (files end in -de), in Germany's region (de_DE)
#   SHOT_LOCALE=de_AT: another region for SHOT_LANG
# Times use each locale's own clock ("23:17" in German), not this simulator's 24-Hour Time switch
# (`AppleICUForce12HourTime`), which the app honours as a user's setting.
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
case $LANG_SHOT in
  de) LOCALE_SHOT=${SHOT_LOCALE:-de_DE} ;;
  *) LOCALE_SHOT=${SHOT_LOCALE:-$LANG_SHOT} ;;
esac
for scheme in dark light; do
  for tab in $TABS; do
    xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
    case $tab in
      notifications|invite|consent|aboutYou|aboutYouSaved|accountHint|signInMethods|syncDetails|baselineSleepNeed|sleepNeed|bedtime|tonight|report-problem*|refresh-details*) set -- -RyftScreen "$tab" ;;
      import|pending|calibrating|watch|waitingForSleep|pendingNoPrevious|recalculating|recalculatingYesterday|needsVitals|needsVitalsBaselines|nightGap|scoringSlow|blockedHRV|blockedNoNight|blockedOura|learningHRV|learningRestingHR|learningRestingHRScored|blockedEarly)
        set -- -RyftTab today -RyftScenario "$tab" ;;
      *) set -- -RyftTab "$tab" ;;
    esac
    name="$tab-$scheme"
    if [ -n "$LANG_SHOT" ]; then
      set -- "$@" -AppleLanguages "($LANG_SHOT)" -AppleLocale "$LOCALE_SHOT"
      name="$name-$LANG_SHOT"
    fi
    xcrun simctl launch "$DEVICE" "$BUNDLE" -demoMode YES "$@" -appearance "$scheme" -AppleICUForce12HourTime NO >/dev/null
    sleep "${SHOT_DELAY:-3}"
    xcrun simctl io "$DEVICE" screenshot --type=png "$OUT/$name.png" >/dev/null 2>&1
    echo "$OUT/$name.png"
  done
done
