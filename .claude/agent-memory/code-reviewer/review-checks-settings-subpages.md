---
name: review-checks-settings-subpages
description: RYFT review checks for restyled settings subpages (Nocturne PR 6 C1: Report a problem, Notifications, Journal settings + Add a habit, 2026-11-19) - vertical TextField losing lineLimit, "nothing changed" copy vs lost responses, List-row notices that never announce, tap guards on enabled-looking switches, whole-list replaces without order, shot-harness artifacts
metadata:
  type: feedback
---

Found in the C1 review (read-only, no build, 2026-11-19); behaviour and identifiers were intact, the suite green:
- **A vertical `TextField` moved into `FormField` lost `.lineLimit(6...)`**: the text view is one line tall, so its prompt
  truncates from AX1 ("What happened?..."), and a background tap-catcher was added to cover the dead card area. Compare the
  *empty* before/after AX3 shots (before wrapped to 3 lines). Fix: `lineLimit(n..., reservesSpace: true)`.
- **"Nothing changed; try again" copy** on every non-offline error: false for a timeout/lost response (the platform may have
  applied it) and for deterministic 422s (custom-behavior cap 50, rune vs grapheme length) where retrying never works.
  `POST /v1/behaviors` is idempotent by app id, but the sheet makes a new UUID per tap, so the retry the copy invites
  duplicates. Read API.md's write semantics (idempotent? cap?) before accepting a generic failure sentence.
- **`InlineMessage` announces in `.onAppear`**: as a `List` row it is lazy, so a failure inserted at the top while the
  user works at the bottom is neither seen nor spoken. Announce from the catch, not the row.
- **"One change at a time" guards** (`guard pending == nil, !model.saving else { return }`) that disable only the pending
  switch: the others look enabled and drop taps silently. Disable everything the guard blocks.
- **Whole-list responses applied without order** (`replace(list)` from PATCH, joined read flights, retries): an older
  answer lands after a newer write and reverts it. Pre-existing in `JournalStore`; ask for a write sequence.
- Not findings: `PagedWindowShot` draws a pinned bar once per page (doubled pill in stitched shots); hosted
  `node.activate()` is `accessibilityActivate`, so it never proves a finger tap reaches an overlay button (trash over a
  switch row) - ask for an XCUITest tap.
- Test helpers: `isSwitch` accepting `.button` while another test filters `.toggleButton` = one of them is vacuous; a colour
  test comparing `color(x) == DeltaLabel.goodColor(x)` mirrors the implementation (and its title claimed "never teal" while
  HRV is teal by F5).
- Shots missed the approved draft's main state (quiet hours on: From/Until chips never rendered, nor at AX3).
- A page that first combines `List` + `.swipeActions` + the bar-hidden back-swipe keeper: check the other area's keeper fix
  (A's 32343e8 forwards UIKit's delegate) is on the base; C's base did not have it.

**Why:** none of these showed in the green suite; they needed the AX3 before-shot, API.md's POST rules, the platform's 422
text, and List laziness. **How to apply:** any Nocturne settings/form subpage. See [[review-checks-form-restyles]],
[[review-checks-screen-restyles]], [[review-checks-async-write-queues]], [[review-checks-large-text]].
