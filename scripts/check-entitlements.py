#!/usr/bin/env python3
"""Guards Ryft.entitlements (CLAUDE.md → signing).

Every key must have a matching capability in Signing & Capabilities. iOS refuses
to launch a build whose entitlements ask for more than the profile grants: an
empty `associated-domains` array once did exactly that ("inadequate
entitlements"). So this fails on:

- a key outside the allow-list below (add it through + Capability, then here), and
- an empty array value, except `healthkit.access`, which Xcode's HealthKit
  capability writes as an empty array when clinical records are off.
"""
import plistlib
import sys

PATH = "Ryft/Ryft.entitlements"
PREFIX = "com.apple.developer."
ALLOWED = {
    "aps-environment",
    PREFIX + "applesignin",
    PREFIX + "healthkit",
    PREFIX + "healthkit.access",
    PREFIX + "healthkit.background-delivery",
}
EMPTY_ARRAY_OK = {PREFIX + "healthkit.access"}


def main() -> int:
    with open(PATH, "rb") as f:
        entitlements = plistlib.load(f)
    problems = []
    for key, value in entitlements.items():
        if key not in ALLOWED:
            problems.append(f"{key}: not in the allow-list (add capabilities through Signing & Capabilities → + Capability)")
        if isinstance(value, list) and not value and key not in EMPTY_ARRAY_OK:
            problems.append(f"{key}: empty array — the profile won't grant it; remove the key or add the capability")
    for p in problems:
        print(f"{PATH}: {p}")
    if problems:
        print(f"\n{len(problems)} entitlement problem(s).")
        return 1
    print(f"Entitlements: {len(entitlements)} keys, all allowed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
