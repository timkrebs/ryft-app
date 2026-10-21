#!/usr/bin/env python3
"""Pulls the response examples out of the platform's docs/API.md (Contract job, docs/CI.md).

Each ```json block is matched to the app type it should decode into by the heading
above it (MAP below). API.md uses a little shorthand that isn't JSON — `{ … }`,
`[ X, … ]`, `"a7f2…"`, `// comments` — which is turned into the smallest valid
equivalent. Type placeholders (`"exercise": Exercise`) are replaced by that type's own example
from earlier in MAP, lists of them (`[ Set, … ]`) by `[]`. Anything still not JSON
is reported as skipped and fails the job, so new shorthand can't switch a check off.

    extract.py <API.md> <out-dir>   →  <out-dir>/<Type>[-n].json + manifest.tsv
"""
import json, re, sys
from pathlib import Path

# heading substring → (Swift type to decode, which block under that heading: 0-based)
MAP = [
    ("`POST /v1/sync`", "SyncResponse", 0),
    ("`GET /v1/me` —", "User", 0),
    ("`DELETE /v1/me` —", "AccountDeleted", 0),
    ("`GET /v1/config`", "RemoteConfig", 0),
    ("`GET /v1/me/sync`", "SyncStatus", 0),
    ("`GET /v1/model`", "ModelInfo", 0),
    ("`PATCH /v1/me/notifications`", "NotificationPrefs", 0),
    ("### Push notifications", "PushPayload", 0),
    ("`GET /v1/days?from", "DailyScore", 0),
    ("`GET /v1/days/{day}`", "SleepDetail", 1),
    ("`GET /v1/days/{day}`", "DayStrain", 2),
    ("`GET /v1/sleep?range", "SleepRange", 0),
    ("`GET /v1/sleep/plan", "SleepPlan", 0),
    ("`GET /v1/workouts/{id}`", "WorkoutDetail", 0),
    ("`GET /v1/trends?", "TrendSeries", 0),
    ("`GET /v1/insights`", "[Insight]", 0),
    ("`GET /v1/exercises?", "[Exercise]", 0),
    ("`GET /v1/exercises/{id}/history", "ExerciseHistory", 0),
    ("`GET /v1/plans/{id}`", "Plan", 0),
    ("`PUT /v1/sessions/{id}`", "TrainSession", 0),
    ("`GET /v1/sessions?", "[SessionSummary]", 0),
    ("`GET /v1/behaviors` —", "[Behavior]", 0),
    ("`GET /v1/journal/{day}`", "JournalDay", 0),
    ("`GET /v1/behaviors/impact`", "BehaviorImpacts", 0),
]

UUID = "00000000-0000-4000-8000-000000000000"
STAMP = "2026-10-19T00:00:00Z"


def clean(text: str) -> str:
    text = re.sub(r"//[^\n\"]*$", "", text, flags=re.M)              # jsonc comments
    text = re.sub(r"\{\s*…\s*\}", "{}", text)                        # { … }
    text = re.sub(r"\[\s*…\s*\]", "[]", text)                        # [ … ]
    text = re.sub(r",\s*…\s*(?=[\]}])", "", text)                    # [ a, b, … ]  { a, … }
    text = re.sub(r'("[a-z_]*(?:_at|^t|start|end|wake|bed)"\s*:\s*)"…"', rf'\1"{STAMP}"', text)
    text = re.sub(r'"(?:[0-9a-f]{2,}(?:-[0-9a-f]+)*)?…[0-9a-f]*"', f'"{UUID}"', text)  # "a7f2…", "…"
    return text


def resolve(text: str, known: dict) -> str:
    text = re.sub(r"\[\s*[A-Z]\w*\s*\]", "[]", text)
    return re.sub(r"(?<=:)\s*([A-Z]\w*)\b(?=\s*[,}])",
                  lambda m: " " + known.get(m.group(1), m.group(1)), text)


def main() -> int:
    doc = Path(sys.argv[1]).read_text()
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    blocks = {}  # heading → [bodies]
    head = ""
    for m in re.finditer(r"^(#{2,4} [^\n]*)$|^```(?:json|jsonc)\n(.*?)\n```", doc, re.M | re.S):
        if m.group(1):
            head = m.group(1)
        else:
            blocks.setdefault(head, []).append(m.group(2))
    rows, failed, known = [], 0, {}
    for needle, typ, index in MAP:
        found = [b for h, bs in blocks.items() if needle in h for b in bs]
        if index >= len(found):
            print(f"missing: no example #{index} under a heading with {needle}")
            failed += 1
            continue
        body = resolve(clean(found[index]), known)
        name = re.sub(r"[\[\]]", "", typ) + ("-list" if typ.startswith("[") else "")
        try:
            json.loads(body)
        except json.JSONDecodeError as e:
            rows.append((typ, name, "skipped", f"shorthand in API.md ({e.msg})"))
            failed += 1
            continue
        (out / f"{name}.json").write_text(body)
        value = json.loads(body)
        element = value[0] if typ.startswith("[") and value else value
        known[typ.strip("[]")] = json.dumps(element)
        rows.append((typ, name, "decode", needle))
    with open(out / "manifest.tsv", "w") as f:
        for r in rows:
            f.write("\t".join(r) + "\n")
    for r in rows:
        print(f"{r[2]:8} {r[0]:20} {r[3]}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
