---
name: copilot-review-threads
description: Copilot's PR review threads block RYFT auto-merges (ruleset requires resolved threads); a PR that sits BLOCKED with every check green usually has one
metadata:
  type: project
---

The `main` ruleset has `required_review_thread_resolution: true`, and `copilot-pull-request-reviewer` comments on PRs on its own.
An unresolved Copilot thread keeps a PR `BLOCKED` with auto-merge on and every required check green, and nothing in
`gh pr checks` says why.

**Why:** on 2026-11-18, #121 sat BLOCKED for an hour after its CI went green. Copilot's thread (written hours earlier) was
a real regression: a new init parameter shadowed the stored `liveActivity`, so the launch no longer ended stale Live
Activities. Two code-reviewer rounds had missed it.

**How to apply:**
- After opening a PR and again before calling it ready, list unresolved threads:
  `gh api graphql -f query='query{repository(owner:"timkrebs",name:"ryft-app"){pullRequest(number:N){reviewThreads(first:50){nodes{id isResolved path line comments(first:1){nodes{author{login} body}}}}}}}'`
- Treat each as a review finding: verify it in the code, then fix or answer it.
- Then reply with `addPullRequestReviewThreadReply` and resolve it with `resolveReviewThread`.
- A fix push restarts CI; see [[integration-branch]] for the queue cost.
