#!/bin/bash
# Formats a Swift file after an agent edited it (PostToolUse on Edit|Write). Never blocks.
INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | /usr/bin/python3 -c "import json,sys; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null)
case "$FILE" in
  *.swift)
    if command -v swiftformat >/dev/null 2>&1; then
      swiftformat --quiet --config "${CLAUDE_PROJECT_DIR:-.}/.swiftformat" "$FILE" >/dev/null 2>&1 || true
    fi ;;
esac
exit 0
