---
name: big-programs-parallel
description: For a large multi-stream program the user wants a written plan plus many agents working in parallel, not one stream at a time
metadata:
  type: feedback
---

When a request spans several streams (e.g. "beta ready": the Nocturne PR 5 and PR 6 restyle, P1b, the wipe recovery, iOS 17/18
checks, the domain PR), the user wants a proper plan **and** parallel execution with more agents. On 2026-11-18 he wrote: "Arbeite
wenn möglich parallel daran und deploye mehr agents" and "Machen einen ordentlichen plan und setzte um". He answered the batched
proposals with a short "ok sehr gut".

**Why:** he values speed to the External beta, and he is happy to approve batched defaults in one line.

**How to apply:**
- Write the plan: streams, owners, dependencies, the critical path, and a "Needs you" list.
- Start every independent stream at once: its own worktree, simulator and DerivedData for each ([[parallel-worktrees]]).
- **At most 5 agents that build or boot a simulator at once** (48 GB RAM, 12 cores, and the Mac is also the CI runner).
  Designers that render drafts count as builders. On 2026-11-18, 10 agents with about 12 simulators caused trouble within
  1.5 h: swap reached 44 GB, the disk went from 63 to 5.5 GB free, and the load went past 800. Recovery:
  - shut down and `simctl delete` the simulators of agents that had finished;
  - delete their `build/` folders;
  - `TaskStop` an agent whose shell hung on `python3 -`, which was waiting on stdin.
- **CI is a builder too.** The self-hosted runner is this Mac, and it runs one job at a time.
  - With 5 agents building, the load swings between 14 and 1000. The UI smoke step (15-minute cap) then times out at 30–126 s
    per test, and CI simulators go missing ("Unable to find a device"). That blocks every merge.
  - **While PRs wait on CI, run at most 4 local builders.** Cancel queued runs that aren't urgent, such as a PR held for C2;
    rerun them when the Mac is quiet.
  - **4 wasn't enough either** (2026-11-18): four screen agents each running strict builds pushed the load to 400+, and #122's UI
    smoke timed out at 15 minutes with every test so far passing. Put this in every builder's brief from the start: before
    each `xcodebuild`, `xcrun simctl list devices booted | grep -q "RYFT CI"`; a match means a CI job is in its test steps,
    so do non-build work or wait. A load rule alone ("over 200 → wait") wasn't followed reliably.
- Check `sysctl vm.swapusage`, `df -h /System/Volumes/Data` and `uptime` before starting another builder. Delete each agent's
  simulator and `build/` as soon as it reports.
- Ask the user's questions batched, each with a recommended default, so one "ok" settles them. For design approvals this worked
  well (2026-11-18): one private artifact page with every draft per area, the questions numbered F1…Fn, each with "● default",
  and a line saying that "ok" takes all of them and a change only needs its number. He answered with a plain "ok".
- Still serialise writers per file, still trial-merge every PR ([[integration-branch]]), and still merge sets on one day
  ([[nightly-testflight]]).
