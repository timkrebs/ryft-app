# Build gate and string sync (RYFT app)

- `pgrep -f xcodebuild` counts the agent's own zsh wrappers (their command lines contain the word). Count the real binary with `pgrep -x xcodebuild`.
- Foreground `sleep` chains are blocked. Use a background `python3 -c "import time; time.sleep(900)"` and wait for its notification.
- `make strings` runs `make build` first. After a successful build with no source changes, `python3 scripts/sync-strings.py --derived-data build/DerivedData` is the same step.
- The sync adds keys as `{}` and never writes comments, plurals or `en` values. Add those by a line-level edit of the catalog (the file uses ` : ` separators, two-space indent, one key per line) and check with `json.load` plus a semantic diff against HEAD.
- A key whose English comes only from `defaultValue` (for example `workout.strain.caption`) needs an explicit `en` block. The sync docstring says it needs none, which is wrong for the runtime lookup.
- Plurals: a single `%lld` uses `variations.plural`. Several arguments need a `substitutions` entry with `argNum` and `%#@name@` in the value.
