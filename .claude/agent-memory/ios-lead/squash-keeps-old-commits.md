---
name: squash-keeps-old-commits
description: refs/pull/N/head keeps a PR's old commits after squash and branch deletion, so redact before a PR opens, not after
metadata:
  type: reference
---

GitHub keeps `refs/pull/N/head` after a squash and after the branch is deleted. Force-pushing or a later redaction does
not remove what a public PR already showed. Only GitHub Support can purge it.

Read every brief in full before it goes public: on 2026-11-04, #65 carried real health values in a pasted TestFlight
report and real export samples, and a first scan by pattern missed them. See [[public-repo-personal-data]].
