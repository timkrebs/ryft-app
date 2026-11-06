#!/bin/sh
# Renders the training import's screens (RyftTests/Import/ImportScreenshotTests.swift) in English and exports the PNGs to
# OUT_DIR/<screen>-<state>-<lang>-<light|dark>-<default|ax3|ax5>.png. `make ui-shots` runs it.
#
#   scripts/ui-shots.sh ["iPhone 18 Pro"] [OUT_DIR] [DERIVED_DATA]
#
# `xcodebuild -testLanguage` alone doesn't reach the hosted unit tests, so the run sets the simulator's own language
# (and region). That happens on a throwaway simulator of the given device type, deleted at the end, so no shared
# simulator's settings change. The test checks that its language applied.
set -eu
cd "$(dirname "$0")/.."

device_type=${1:-"iPhone 18 Pro"}
out=${2:-build/ui-shots}
derived=${3:-build/DerivedData}

sim=$(xcrun simctl create "RYFT ui-shots" "$device_type")
cleanup() {
    xcrun simctl shutdown "$sim" 2>/dev/null || true
    xcrun simctl delete "$sim" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM

rm -rf "$out"
lang=en
xcrun simctl boot "$sim" 2>/dev/null || true
xcrun simctl spawn "$sim" defaults write -g AppleLanguages -array "$lang"
xcrun simctl spawn "$sim" defaults write -g AppleLocale "en_US"
bundle="build/ui-shots-$lang.xcresult"
rm -rf "$bundle"
# Not parallel: parallel testing runs on clones of the simulator, which don't get its language.
TEST_RUNNER_RYFT_SCREENSHOTS=1 TEST_RUNNER_RYFT_SHOT_LANG="$lang" xcodebuild -scheme Ryft -testPlan Unit \
    -destination "platform=iOS Simulator,id=$sim" -derivedDataPath "$derived" -parallel-testing-enabled NO \
    -only-testing:RyftTests/ImportScreenshotTests -testLanguage "$lang" -testRegion US \
    -resultBundlePath "$bundle" test

# shellcheck disable=SC2086 # one argument per bundle
sh scripts/export-ui-shots.sh "$out" $bundle
echo "$(ls "$out" | wc -l | tr -d ' ') screenshots in $out"
