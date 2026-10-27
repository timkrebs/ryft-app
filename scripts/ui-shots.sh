#!/bin/sh
# Renders the training import's screens (RyftTests/Import/ImportScreenshotTests.swift) once per language and exports
# the PNGs to OUT_DIR/<screen>-<state>-<lang>-<light|dark>-<default|ax3|ax5>.png. `make ui-shots` runs it.
#
#   scripts/ui-shots.sh ["iPhone 18 Pro"] [OUT_DIR] [DERIVED_DATA]
#
# `xcodebuild -testLanguage` alone did not reach the hosted unit tests (the German run rendered English), so each run
# sets the simulator's own language. That happens on a throwaway simulator of the given device type, deleted at the
# end, so no shared simulator's settings change. Each test checks that its language applied.
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
bundles=""
for lang in en de; do
    # xcodebuild shuts the simulator down after a run; it boots again for the next language.
    xcrun simctl boot "$sim" 2>/dev/null || true
    xcrun simctl spawn "$sim" defaults write -g AppleLanguages -array "$lang"
    xcrun simctl spawn "$sim" defaults write -g AppleLocale "${lang}_DE"
    bundle="build/ui-shots-$lang.xcresult"
    rm -rf "$bundle"
    # Not parallel: parallel testing runs on clones of the simulator, which don't get its language.
    TEST_RUNNER_RYFT_SCREENSHOTS=1 TEST_RUNNER_RYFT_SHOT_LANG="$lang" xcodebuild -scheme Ryft -testPlan Unit \
        -destination "platform=iOS Simulator,id=$sim" -derivedDataPath "$derived" -parallel-testing-enabled NO \
        -only-testing:RyftTests/ImportScreenshotTests -testLanguage "$lang" -testRegion DE \
        -resultBundlePath "$bundle" test
    bundles="$bundles $bundle"
done

# shellcheck disable=SC2086 # one argument per bundle
sh scripts/export-ui-shots.sh "$out" $bundles
echo "$(ls "$out" | wc -l | tr -d ' ') screenshots in $out"
