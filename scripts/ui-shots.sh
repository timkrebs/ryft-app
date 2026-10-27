#!/bin/sh
# Renders the training import's screens (RyftTests/Import/ImportScreenshotTests.swift) once per language and exports
# the PNGs to OUT_DIR/<screen>-<state>-<lang>-<light|dark>-<default|ax3|ax5>.png. `make ui-shots` runs it.
#
#   scripts/ui-shots.sh SIMULATOR_UDID [OUT_DIR] [DERIVED_DATA]
#
# `xcodebuild -testLanguage` alone did not reach the hosted unit tests (the German run rendered English), so the
# simulator's own language is set for each run as well and put back afterwards.
set -eu
cd "$(dirname "$0")/.."

sim=${1:?usage: $0 SIMULATOR_UDID [OUT_DIR] [DERIVED_DATA]}
out=${2:-build/ui-shots}
derived=${3:-build/DerivedData}

# xcodebuild shuts the simulator down after a run; every spawn boots it first.
boot() { xcrun simctl boot "$sim" 2>/dev/null || true; }
boot
saved=$(mktemp)
xcrun simctl spawn "$sim" defaults export -g - >"$saved"
restore() {
    boot
    xcrun simctl spawn "$sim" defaults import -g - <"$saved" || true
    rm -f "$saved"
}
trap restore EXIT

rm -rf "$out"
bundles=""
for lang in en de; do
    boot
    xcrun simctl spawn "$sim" defaults write -g AppleLanguages -array "$lang"
    xcrun simctl spawn "$sim" defaults write -g AppleLocale "${lang}_DE"
    bundle="build/ui-shots-$lang.xcresult"
    rm -rf "$bundle"
    # Not parallel: parallel testing runs on clones of the simulator, which don't get its language.
    RYFT_SCREENSHOTS=1 TEST_RUNNER_RYFT_SCREENSHOTS=1 xcodebuild -scheme Ryft -testPlan Unit \
        -destination "platform=iOS Simulator,id=$sim" -derivedDataPath "$derived" -parallel-testing-enabled NO \
        -only-testing:RyftTests/ImportScreenshotTests -testLanguage "$lang" -testRegion DE \
        -resultBundlePath "$bundle" test
    bundles="$bundles $bundle"
done

# shellcheck disable=SC2086 # one argument per bundle
sh scripts/export-ui-shots.sh "$out" $bundles
echo "$(ls "$out" | wc -l | tr -d ' ') screenshots in $out"
