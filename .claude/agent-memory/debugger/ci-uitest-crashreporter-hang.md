---
name: ci-uitest-crashreporter-hang
description: CI UI smoke "exceeded execution time allowance of 1 minute" after the test body passed = XCTest crash-reporter sync stalled on the runner VM, not app code
metadata:
  type: project
---
Seen on PR #27 (runs 39695249665, 39704400045): test body finished in ~12 s and passed, then the runner's `synchronizing with crash reporter` wait (normally 12 ms; Session-*.log in `xcresulttool export diagnostics`) hung while ReportCrash/ReportCrashService were blocked on CoreAnalytics/analyticsd sqlite and getattrlistbulk. App was idle (0.26 s CPU in 62 s, isQuiescent fulfilled). Which test hangs varies (1st in run 1, 5th in run 2).
**How to apply:** before suspecting animations/idle, check the xcresult activities: if "Tear Down" ends and the next gap is the crash-reporter sync, it is runner infra. Verify with `grep "synchronizing with crash reporter"` in Session logs. Mitigate in CI (retry-tests-on-failure, larger allowance), not in app code.
