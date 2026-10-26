#!/bin/sh
# Prints the Developer directory of the Xcode pinned in .xcode-version, for DEVELOPER_DIR.
# GitHub's images install it as /Applications/Xcode_<version>.app; a self-hosted Mac usually
# has /Applications/Xcode.app. Any /Applications/Xcode*.app whose version matches will do.
# No sudo: the caller exports DEVELOPER_DIR instead of running xcode-select, so a
# self-hosted runner never waits for a password and the machine's own selection stays.
set -eu
want="$(tr -d '[:space:]' < .xcode-version)"
for app in "/Applications/Xcode_${want}.app" /Applications/Xcode*.app; do
  [ -d "$app" ] || continue
  have="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/version.plist" 2>/dev/null || true)"
  if [ "$have" = "$want" ]; then
    echo "$app/Contents/Developer"
    exit 0
  fi
done
echo "Xcode $want (.xcode-version) is not on this runner. Installed:" >&2
for app in /Applications/Xcode*.app; do
  [ -d "$app" ] && echo "  $app: $(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/version.plist" 2>/dev/null)" >&2
done
exit 1
