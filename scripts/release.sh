#!/bin/sh
# Cuts a version through a pull request, because `main` takes nothing else (its ruleset wants a PR, linear history
# and the required checks, with no bypass). `make release` runs it (docs/CI.md → Versions and build numbers).
#
#   scripts/release.sh patch|minor|major     # the next version from VERSION
#   scripts/release.sh X.Y.Z                 # an explicit version, above the current one
#   DRY_RUN=1 scripts/release.sh minor       # everything up to the push, shown, then undone
#
# From an up-to-date, clean `main` it creates `release/vX.Y.Z` with VERSION raised and CHANGELOG.md's Unreleased
# entries moved under the new version, pushes it and opens the PR `release: X.Y.Z` with your own `gh` login. A PR a
# person opens runs the required checks; one opened with a workflow's GITHUB_TOKEN would run none and never merge.
# After the squash merge, .github/workflows/release.yml tags vX.Y.Z on that commit and uploads it to TestFlight.
set -eu
cd "$(dirname "$0")/.."

die() {
    echo "release: $*" >&2
    exit 1
}

want=${1:-}
dry=${DRY_RUN:-}
[ "$dry" != 0 ] || dry=
[ -n "$want" ] || die "usage: make release BUMP=patch|minor|major, or make release VERSION=X.Y.Z (DRY_RUN=1 to try)"

# A clean main, equal to origin/main.
[ "$(git symbolic-ref --quiet --short HEAD || true)" = main ] || die "not on main (git switch main)"
[ -z "$(git status --porcelain)" ] || die "the working tree has changes; commit or stash them first"
git fetch --quiet --tags origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || die "main isn't origin/main (git pull)"

semver='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
current=$(tr -d '[:space:]' < VERSION)
echo "$current" | grep -Eq "$semver" || die "VERSION isn't X.Y.Z: $current"
major=${current%%.*}
rest=${current#*.}
minor=${rest%%.*}
patch=${rest#*.}
case $want in
    major) next="$((major + 1)).0.0" ;;
    minor) next="$major.$((minor + 1)).0" ;;
    patch) next="$major.$minor.$((patch + 1))" ;;
    *) next=$want ;;
esac
echo "$next" | grep -Eq "$semver" || die "not patch, minor, major or X.Y.Z: $want"
highest=$(printf '%s\n%s\n' "$current" "$next" | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)
if [ "$next" = "$current" ] || [ "$highest" != "$next" ]; then
    die "$next isn't above the current version $current"
fi

tag="v$next"
branch="release/$tag"
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    die "the tag $tag exists (if it's only a local leftover: git tag -d $tag)"
fi
if git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null; then
    die "the tag $tag exists on origin"
fi
if git rev-parse -q --verify "refs/heads/$branch" >/dev/null; then
    die "the branch $branch exists here"
fi
if git ls-remote --exit-code --heads origin "refs/heads/$branch" >/dev/null; then
    die "the branch $branch exists on origin (an open release PR?)"
fi
[ "$(grep -cx '## \[Unreleased\]' CHANGELOG.md)" = 1 ] || die "CHANGELOG.md needs exactly one '## [Unreleased]' heading"
if [ -z "$dry" ]; then
    gh auth status >/dev/null 2>&1 || die "gh isn't logged in (gh auth login)"
fi

# The commits since the last version, the same list release.yml sends to TestFlight after the merge.
last=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)
range=HEAD
[ -z "$last" ] || range="$last..HEAD"
log=$(git log --no-merges --pretty='- %s' -n 40 "$range")

body=
made_branch=
cleanup() {
    rm -f "$body"
    if [ -n "$dry" ] && [ -n "$made_branch" ]; then
        git checkout --quiet --force main
        git branch --quiet -D "$branch"
        echo "DRY_RUN: back on main, $branch deleted; nothing was pushed."
    fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

git switch --quiet -c "$branch"
made_branch=1
printf '%s\n' "$next" > VERSION
# Keep a Changelog: the new version's heading goes right under Unreleased, which takes everything that was there.
awk -v heading="## [$next] - $(date +%Y-%m-%d)" '
    { print }
    $0 == "## [Unreleased]" { print ""; print heading }
' CHANGELOG.md > CHANGELOG.md.tmp
mv CHANGELOG.md.tmp CHANGELOG.md
git add VERSION CHANGELOG.md
git commit --quiet -m "release: $next"

body=$(mktemp)
{
    echo "Raises \`VERSION\` from $current to $next and moves \`CHANGELOG.md\`'s Unreleased entries under [$next]."
    echo
    echo "After the squash merge, \`release.yml\` tags \`$tag\` on the merge commit and uploads that tag to TestFlight"
    echo "(group Internal). What to Test will be (plus anything merged before this PR):"
    echo
    echo '```'
    echo "RYFT $next"
    echo "$log"
    echo '```'
} > "$body"

if [ -n "$dry" ]; then
    echo "DRY_RUN: would push $branch and open the PR 'release: $next' against main."
    echo
    git --no-pager show --stat --patch -U1 HEAD
    echo
    echo "PR body:"
    cat "$body"
    exit 0
fi

git push --quiet --set-upstream origin "$branch"
gh pr create --base main --head "$branch" --title "release: $next" --body-file "$body"
echo "Merge the PR when its checks are green; release.yml then tags $tag and uploads it to TestFlight."
