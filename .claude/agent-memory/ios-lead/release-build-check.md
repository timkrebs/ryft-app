---
name: release-build-check
description: PR CI builds Debug only; the TestFlight archive is the first Release compile. Every integration run needs a Release build too
metadata:
  type: project
---

PR checks (`ios.yml` build-for-testing, `security.yml`) build only Debug. The first Release compile is the archive in
`_testflight.yml`. A Debug-only symbol (anything under `#if DEBUG`, such as a preview mock graph) used in a `#Preview` body
or a helper outside `#if DEBUG` passes every PR check and only breaks the nightly archive. `#Preview` bodies are
type-checked in Release.

**Why:** on 2026-11-19 the PR 6 C seams review found `MockDevicesStates` (DEBUG-only) used in five Profile files' previews.
Its integration run was fully green (strict build, Unit plan, lint, style), because all of those are Debug.

**How to apply:**
- Every integration run and every "done means" adds
  `xcodebuild -scheme Ryft -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`.
- Briefs that add preview-only mocks say "wrap the previews in `#if DEBUG`".
- A CI Release build (or a lint) belongs in a `ci:` PR.
- See [[nightly-signing-blocked]]: with the archive already failing for signing, a compile break would hide behind it.
