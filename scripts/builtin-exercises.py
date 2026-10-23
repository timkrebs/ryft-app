#!/usr/bin/env python3
"""The training import's tests match against `RyftTests/Fixtures/Import/builtin-exercises.json`, a snapshot of the
platform's built-in exercise library (`backend/internal/db/seed/exercises.json` in the platform checkout) in the
`GET /v1/exercises` shape, with the platform's fixed ids: uuid5(namespace, "exercise:<slug>"), as
`backend/internal/train/train.go` derives them. The alias catalogue points at these slugs.

    python3 scripts/builtin-exercises.py            # --check: the snapshot still equals the seed (make lint)
    python3 scripts/builtin-exercises.py --write    # regenerate the snapshot from the seed

The platform checkout is read only. Without one (CI, a worktree elsewhere) the check is skipped quietly; pass
`--platform DIR` or set RYFT_PLATFORM_DIR to point at it.
"""
import argparse
import json
import os
import sys
import uuid

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
FIXTURE = os.path.join(ROOT, "RyftTests", "Fixtures", "Import", "builtin-exercises.json")
SEED = os.path.join("backend", "internal", "db", "seed", "exercises.json")
NAMESPACE = uuid.UUID("1c7e3b9a-5d2f-4e8b-9a61-3f0d2c4b7e15")


def snapshot(seed):
    out = []
    for e in seed:
        out.append({
            "id": str(uuid.uuid5(NAMESPACE, "exercise:" + e["slug"])),
            "slug": e["slug"],
            "name": e["name_en"],
            "name_en": e["name_en"],
            "name_de": e["name_de"],
            "kind": e["kind"],
            "primary_muscles": e["primary_muscles"],
            "secondary_muscles": e["secondary_muscles"],
            "equipment": e["equipment"],
            "load_type": e["load_type"],
            "bodyweight_factor": e["bodyweight_factor"],
            "is_unilateral": e["is_unilateral"],
            "is_custom": False,
            "archived": False,
        })
    return out


def render(entries):
    lines = ("  " + json.dumps(e, ensure_ascii=False, separators=(", ", ": ")) for e in entries)
    return "[\n" + ",\n".join(lines) + "\n]\n"


def main():
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="the snapshot still equals the seed (the default)")
    mode.add_argument("--write", action="store_true", help="regenerate the snapshot from the seed")
    parser.add_argument("--platform", default=os.environ.get("RYFT_PLATFORM_DIR", os.path.join(ROOT, "..", "plattform")))
    args = parser.parse_args()

    # The id recipe itself, against the example in API.md.
    assert str(uuid.uuid5(NAMESPACE, "exercise:back-squat")) == "053b5627-084e-5417-a033-a6602d812f86"

    seed_path = os.path.join(args.platform, SEED)
    if not os.path.isfile(seed_path):
        print("Built-in exercises: no platform checkout, check skipped.")
        return 0
    with open(seed_path, encoding="utf-8") as f:
        expected = render(snapshot(json.load(f)))

    if args.write:
        with open(FIXTURE, "w", encoding="utf-8") as f:
            f.write(expected)
        print(f"Built-in exercises: {FIXTURE} written.")
        return 0

    with open(FIXTURE, encoding="utf-8") as f:
        actual = f.read()
    if actual == expected:
        print(f"Built-in exercises: snapshot matches the platform seed ({expected.count(chr(10)) - 2} exercises).")
        return 0
    seed = {e["slug"]: e for e in json.loads(expected)}
    fixture = {e["slug"]: e for e in json.loads(actual)}
    for slug in sorted(seed.keys() - fixture.keys()):
        print(f"  new on the platform: {slug}")
    for slug in sorted(fixture.keys() - seed.keys()):
        print(f"  gone from the platform: {slug}")
    for slug in sorted(seed.keys() & fixture.keys()):
        changed = sorted(k for k in seed[slug] if seed[slug][k] != fixture[slug].get(k))
        if changed:
            print(f"  changed: {slug} ({', '.join(changed)})")
    print("Built-in exercises: the snapshot differs from the platform seed. "
          "Run `python3 scripts/builtin-exercises.py --write`, then check the alias catalogue's tests.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
