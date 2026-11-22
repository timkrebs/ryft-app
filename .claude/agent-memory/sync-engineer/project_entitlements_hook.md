---
name: project-entitlements-hook
description: pre-edit-guard.sh refuses any Edit of *.entitlements even when a brief or plan asks for it; report and give the Xcode + Capability steps
metadata:
  type: project
---

On 2026-11-19 (App Attest T2) the brief and plan.md both said to write
`com.apple.developer.devicecheck.appattest-environment = production` into `Ryft/Ryft.entitlements`; the Edit was refused
by `.claude/hooks/pre-edit-guard.sh` ("entitlements change only via Xcode → Signing & Capabilities → + Capability").
`scripts/check-entitlements.py` (allow-list, and since round 2 a required `production` value) is editable.

**Why:** CLAUDE.md's signing rule is enforced by the hook, not just written down; an agent brief can't lift it.

**How to apply:** never route around it (no Bash writes to the file). Make the script/allow-list change, then report
the user step: Xcode → target Ryft → Signing & Capabilities → + Capability → App Attest, then set the value to
`production` (Xcode writes `development`). Related: [[project-simulator-and-tools]].
