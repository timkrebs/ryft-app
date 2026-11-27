---
name: HTML mock drafts for spec-only tickets
description: Fast way to draw Nocturne list pages without building the app, and Nocturne facts that shaped the N1 notifications spec
type: reference
---
Spec-only ticket (no code, no simulator): a python generator emitting HTML with the Nocturne tokens (bg #0A0C0B, surface #121514, raised #2F312F, text #F2F1EC at 100/62/48 %, separator 8 %, warning #E3C25B), rendered with `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --headless=new --screenshot=... --window-size=W,H file://...`. Good enough to judge hierarchy and copy length; font is a stand-in. On macOS use `sed -i ''`.
- Catalog keys are the English text (house style); server loc-keys are UPPER_SNAKE. NBSP before units and `%` is a real U+00A0.
- SwiftUI `DatePicker` has no minuteInterval; 15-minute steps need a UIDatePicker behind `ValueChip`.
- `GroupedRow` value trailing does not shrink the title until AX1: long values go in the detail line.
- Today starts a sync on open, so "last sync > 20 h" is rare there; say so in specs.
