---
name: simulator-language
description: Agents switching a simulator to German must never use `defaults write <path>/.GlobalPreferences`; it hit the Mac's global prefs on 2026-10-31
metadata:
  type: feedback
---

To run tests in German, only change the simulator itself, never the Mac. Use `xcrun simctl spawn <udid> defaults write -g AppleLanguages -array de-DE` (and AppleLocale), or `plutil -replace` on the device's `.GlobalPreferences.plist` with the full `.plist` path. Never use `defaults write "<path>/.GlobalPreferences"`.

**Why:** On 2026-10-31 a localization-editor ran `defaults write ".../Devices/<udid>/data/Library/Preferences/.GlobalPreferences" AppleLanguages -array de`. It changed the user's Mac instead of the simulator: AppleLanguages became (de) and AppleLocale de_DE. Every simulator created after that came up in German, and 102 English text tests failed on CI. CI runs on this Mac, see [[ci-ui-timeouts]]. The user approved restoring his original values: AppleLanguages (en-US, de-DE), AppleLocale `en_US@rg=dezzzz`. Those values were read from a simulator created earlier that day, because new simulators copy the Mac's settings.

**How to apply:**
- Put this rule in every brief that asks for a run in German.
- `xcodebuild -testLanguage de` doesn't reach the hosted Swift Testing run.
- When text tests fail all at once on CI, run `defaults read -g AppleLanguages` first.
- Follow-up idea: the CI script could set each simulator it creates to en-US, so CI no longer depends on the Mac's language.
