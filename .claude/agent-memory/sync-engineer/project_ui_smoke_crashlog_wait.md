---
name: project-ui-smoke-crashlog-wait
description: CI UI smoke "exceeded execution time allowance" / "Failed to terminate dev.timkrebs.ryft" was XCTest waiting for crash logs, not the app; how to tell
metadata:
  type: project
---

PR #27 (2026-10-22): UI smoke failed with NotificationsUITests exceeding 60 s in Tear Down, then StoreSmoke
"Failed to terminate dev.timkrebs.ryft:<pid>". The CI `test-results` artifact's UISmoke.xcresult had a spindump:
the app was idle and frontmost (main thread in mach_msg, ~0 CPU), the runner sat in
`-[XCTestCase _waitForPendingCrashlogsIfNeeded]` (XCTCrashLogTracker), and the host's ReportCrash was symbolicating
5 reports. A control run of another PR's build showed the same tear-down waits locally (10–20 s), and iOS 27
simulators crash PosterBoard often (`~/Library/Logs/DiagnosticReports/PosterBoard-*.ips`).

**Why:** the reviewer suspected cancellation-blind waits in the app; the evidence ruled that out. Re-running is
the right answer for this signature, not app changes.

**How to apply:** for a hang in Tear Down or a failed terminate, first `gh run download <run> -n test-results`,
`xcresulttool get test-results activities --test-id …` and `export attachments`, read the app's and the
runner's threads in the spindump; compare with a control build before touching code. Related:
[[project-dev-machine-disk]].
