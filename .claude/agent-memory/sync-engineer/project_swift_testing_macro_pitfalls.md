---
name: project-swift-testing-macro-pitfalls
description: Swift Testing macro forms that break the RyftTests build under RYFT_STRICT_WARNINGS (nested #require, #require on a mutating call, heavy static literals)
metadata:
  type: project
---

Seen 2026-10-23 (A3a track pipeline), Xcode 27.1, `RYFT_STRICT_WARNINGS=YES`:

- `#require(f(#require(x)))` and `try #require(…)` inside `#expect(…)`: "recursive expansion of macro 'require'". Bind
  the inner value to a `let` first.
- `try #require(p.lap(at:))` where `lap` is `mutating`: the macro expands without a throwing call, so "no calls to
  throwing functions occur within 'try'" becomes an error. Call first, then `#require` the result.
- `static let x = (0..<30).map { Struct(…, a: i % 7 == 0 ? nil : …) }` and big tuple-array literals mixing Int and
  Double: "unable to type-check in reasonable time". Use a typed helper function and explicit `Double?` locals; use
  small structs (with `CustomTestStringConvertible`) for parameterised cases instead of 7-tuples.
- (2026-10-23, I2 import parser) A `rethrows` call at the top of `#expect`, e.g. `#expect(xs.allSatisfy(\.p))` or
  `#expect(!xs.contains(where: \.p))`: "call can throw, but it is not marked with 'try'". Bind it to a `let` first.
  Inside an `==` operand (`#expect(xs.map(\.a) == […])`) it compiles. Also keep `try` calls out of `#expect`
  operands (`#expect(try f() == g())`): bind them first.

**Why:** each cost a full build-for-testing round trip (~3 min); the emit-module step stops at the first one, so
later errors only show on the next build.

**How to apply:** write new Swift Testing files with these forms avoided from the start. Related:
[[project-dev-machine-disk]] (reuse DerivedData for those rebuilds).
