---
name: locale-tests-device-region
description: Simulators here run en_US@rg=DE, so a locale test that checks only de_DE output passes without the locale parameter; assert two locales with different decimal marks
metadata:
  type: project
---

The simulators on this Mac report `AppleLocale = en_US@rg=DE` (2026-11-20): `Locale.autoupdatingCurrent` formats `12.4` as
"12,4". A test that passes `de_DE` and expects "12,4" therefore also passes when the code ignores the locale it's given; the
mutants for StrainHero's numeral and the summary's load tile survived that way. Conversely an expectation built with
`Fmt.x(value)` (device locale) fails against content made with `en_US` (TrainPlansSummaryTests' load tile did).

**Why:** a locale fix (seams N3) looked tested but wasn't; the hole showed only in the mutant run.

**How to apply:** for "takes the given locale" tests, loop over `en_US` and `de_DE` (different decimal marks) so the device's can't
pass for both; build expectations with the same explicit locale as the content. Check a sim's locale with
`xcrun simctl spawn <udid> defaults read -g AppleLocale`. See [[tests-pin-decisions]].
