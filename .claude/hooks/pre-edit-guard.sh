#!/bin/bash
# Blocks edits the RYFT rules forbid, before they happen (PreToolUse on Edit|Write).
# Exit 2 = blocked; the message on stderr goes back to the agent.
INPUT=$(cat)
field() { printf '%s' "$INPUT" | /usr/bin/python3 -c "import json,sys; d=json.load(sys.stdin).get('tool_input',{}); print(d.get('$1','') or '')" 2>/dev/null; }
FILE=$(field file_path)
NEW="$(field content)$(field new_string)"
ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"

case "$FILE" in
  *.xcodeproj/project.pbxproj)
    echo "Blocked: never hand-edit project.pbxproj. Ryft/, RyftTests/, RyftUITests/ are synchronized folders; build settings and capabilities go through the user in Xcode." >&2; exit 2 ;;
  *.entitlements)
    echo "Blocked: entitlements change only via Xcode → Signing & Capabilities → + Capability. Print the steps for the user." >&2; exit 2 ;;
  */plattform/*)
    echo "Blocked: the app fleet never writes in ../plattform. File the need in docs/API_REQUESTS.md." >&2; exit 2 ;;
esac

# The product never names another wearable brand as a comparison (brand rule).
if printf '%s' "$NEW" | grep -Eiq 'wh[o0]{2}p|w[-. ]h[-. ]o[-. ]o[-. ]p'; then
  echo "Blocked: new text contains a denylisted brand name (see ryft-app-conventions, rule 7). Rephrase without it." >&2; exit 2
fi
exit 0
