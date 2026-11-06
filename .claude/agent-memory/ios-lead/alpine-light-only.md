---
name: alpine-light-only
description: The monochrome Alpine redesign of 2026-11-05 applies to light only, fonts and corners included, until the dark pass; #100 is its PR
metadata:
  type: project
---

The user chose monochrome Alpine for light mode (#100, ADR 0015). On 2026-11-05 he chose **light only, switch by appearance**: Inter
and square corners must not reach dark, even though both were shared constants, because the brief says dark stays unchanged.

**Why:** dark is the shipping look for testers, and a mixed look was the rejected alternative. He accepted that fonts and corners
flip with the system appearance, and that views carry both styles until the dark pass removes them.

**How to apply:** anything new in Design takes the light and dark style from the environment. Verify dark against a before render:
it must not move. The website's token script reads `Theme.swift` and `Typography.swift`, so check it before changing their form.
