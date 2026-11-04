---
name: hosted-test-language
description: xcodebuild -testLanguage didn't localize hosted RyftTests renders; parallel runs use simulator clones; xcodebuild shuts the sim down after a run
metadata:
  type: project
---

On 2026-10-27, `xcodebuild … -testLanguage de -testRegion DE` with `-testPlan Unit` still rendered English in hosted RyftTests, so `Bundle.main.preferredLocalizations` stayed `en`. Two things contributed. Parallel testing runs on "Clone N of <sim>", which doesn't inherit later changes to the simulator. And xcodebuild shuts the original simulator down after the run, so a following `simctl spawn` fails with SimError 405.

**Why:** the German screenshot run of `make ui-shots` silently produced English images with `en` names.

**How to apply:** for any localized render or test run, use `scripts/ui-shots.sh`'s pattern. Run `simctl boot` before each spawn, set `defaults write -g AppleLanguages/AppleLocale`, pass `-parallel-testing-enabled NO`, restore with `defaults export/import -g`. Then check one PNG visually, not just the file names. Also note that a direct `xcodebuild`/`sh` call in compound shell commands gets refused in delegated sessions, while `make <target>` runs. Route repeatable runs through a make target. See [[ci-ui-timeouts]].
