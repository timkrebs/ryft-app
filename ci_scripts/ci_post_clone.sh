#!/bin/sh
# Xcode Cloud runs this after cloning (ci_scripts/ sits next to Ryft.xcodeproj). It does
# what .github/actions/setup does for GitHub Actions: the git-ignored xcconfigs from their
# examples (make config) and the Satoshi fonts, which may not live in the repository
# (make fonts). Without them the project doesn't open its base configuration.
set -eu
cd "${CI_PRIMARY_REPOSITORY_PATH:-$(dirname "$0")/..}"
for c in Debug Release; do
  [ -f "Config/$c.xcconfig" ] || cp "Config/$c.xcconfig.example" "Config/$c.xcconfig"
done
sh scripts/fetch-fonts.sh
