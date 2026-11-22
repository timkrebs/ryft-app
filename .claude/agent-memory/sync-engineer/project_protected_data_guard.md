---
name: project-protected-data-guard
description: UIApplication.isProtectedDataAvailable is false whenever the iPhone is locked, not only before the first unlock; guard only the destructive branches with it
metadata:
  type: project
---

`UIApplication.shared.isProtectedDataAvailable` follows complete file protection: false whenever the device is locked
(about 10 s after locking), not only before the first unlock after a reboot. Keychain items with `afterFirstUnlock`
and UserDefaults stay readable while locked once the device has been unlocked once.

**Why:** in N3 round 2 (2026-11-22, review S-2) I first put the guard at the top of `ReminderScheduler.pass()`. That
would have made every locked BG refresh and HealthKit-delivery pass decide nothing, so the fallback wouldn't follow a
background sync. The real risk is narrower. Before the first unlock the session can look signed out and the owner key
can read empty, so the destructive branches would tear down and clear Notification Center.

**How to apply:** use the guard only on branches that remove things for "nobody" or for another account (the signed-out
teardown, the owner mismatch). Ordinary planning goes on while locked. Test it with an overridable closure
(`scheduler.isProtectedDataAvailable = { false }`).
