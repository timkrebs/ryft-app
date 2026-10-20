#!/usr/bin/env python3
"""Line coverage of the Ryft target per area, against a floor (docs/CI.md → Coverage).

    xcrun xccov view --report --json build/Unit.xcresult > build/coverage.json
    scripts/coverage.py build/coverage.json [--summary "$GITHUB_STEP_SUMMARY"]

Prints a Markdown table (appended to the job summary when --summary is given) and
exits 1 when an area in scripts/coverage-floor.json dropped below its floor. The
floors are the numbers measured when they were set, minus 2 points; raise them when
coverage goes up for good, never lower them to get a PR through.
"""
import argparse, fnmatch, json, sys
from pathlib import Path

AREAS = {
    "Networking": "*/Ryft/Networking/*",
    "Sync": "*/Ryft/Sync/*",
    "Persistence": "*/Ryft/Persistence/*",
    "View models": "*/Ryft/Features/*ViewModel*.swift",
}
FLOORS = Path(__file__).with_name("coverage-floor.json")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("report")
    ap.add_argument("--summary")
    args = ap.parse_args()
    report = json.loads(Path(args.report).read_text())
    files = [f for t in report["targets"] if t["name"] == "Ryft.app" for f in t["files"]]
    if not files:
        print("No Ryft.app target in the coverage report; is coverage on in the test plan?")
        return 1
    floors = json.loads(FLOORS.read_text())

    def pct(fs):
        lines = sum(f["executableLines"] for f in fs)
        return 100 * sum(f["coveredLines"] for f in fs) / lines if lines else None

    rows = [("Ryft (all)", pct(files), None)]
    for area, pattern in AREAS.items():
        rows.append((area, pct([f for f in files if fnmatch.fnmatch(f["path"], pattern)]), floors.get(area)))

    out = ["### Coverage (Ryft target)", "", "| Area | Lines | Floor | |", "| --- | ---: | ---: | --- |"]
    failed = []
    for area, value, floor in rows:
        shown = "–" if value is None else f"{value:.1f} %"
        verdict = ""
        if floor is not None:
            ok = value is not None and value + 1e-9 >= floor
            verdict = "ok" if ok else "**below floor**"
            if not ok:
                failed.append(area)
        out.append(f"| {area} | {shown} | {'' if floor is None else f'{floor:.1f} %'} | {verdict} |")
    text = "\n".join(out) + "\n"
    print(text)
    if args.summary:
        with open(args.summary, "a") as f:
            f.write(text)
    if failed:
        print(f"::error::Coverage below the floor in {', '.join(failed)} (scripts/coverage-floor.json)")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
