---
name: project-editor-saves-never-wait
description: Autosave editors in RYFT save synchronously and run side effects in passes; never chain a save behind the previous save's network or alarm work
metadata:
  type: project
---

An autosave editor (debounce, then save) must save synchronously when the wait ends: bump a generation, set the model,
write defaults. Reminders, alarms and the network follow in one-at-a-time passes that read the model as it is when
they start and stop after every await if the generation or the owner (AccountBinding + StoreEpoch) changed. The GET
runs in a stored, cancellable Task so a new change or Turn off cancels it instead of waiting for it.

**Why:** C4 review (2026-11-19) blocked Bedtime & wake because the second change waited for the first change's
`GET /v1/sleep/plan`, and a sign-out between the wipe and `accountChanged()` let stale work write under the next account.

**How to apply:** any editor that saves on change (Bedtime & wake, body settings, sleep need): one editor per model
(owned by it, so every entry point shares the copy), record the owner on the first change, drop the save if the owner
changed, and guard every cache write with the epoch. Test with held seams (a CheckedContinuation gate on the mock's
`before…` hook, cancellation-aware) rather than sleeps.
