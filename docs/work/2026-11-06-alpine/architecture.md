# Alpine: architecture for the six PRs

Reads with [`plan.md`](plan.md), which wins any conflict, then [`brief.md`](brief.md) and [`design.md`](design.md). This note changes no Swift and
nothing in `../plattform`. It replaces the light-only version: `RyftLook`, `RyftCorner`, `dark-diff` and `ClassicLookTests` are gone.

Verified means run on 2026-11-06 against #100's tree, on scratch copies, with `tokens.mjs` from `web/alpine` (#143) at `c67b515`. Nothing here ran on a
simulator.

## 1. Summary

- **PR 1 can't be "tests and the icon SVG".** Two of the six pins need the drawing. PR 1 takes the gauge's two non-colour cues from PR 3: the ring by
  level and the hatch past the band. No test is disabled (section 5.1).
- **`RYFT_APP_DIR=.. npm run tokens:check` checks nothing and exits 0.** Section 3.1 has the command that works.
- **Merging #100 breaks platform CI twice**, and the brief removes `ref:` too late. Platform has four steps, the first before PR 1 merges (section 3.4).
- **Only one form makes `tokens.mjs` throw for a good reason:** the wordmark's minus. `cardRadius = 0`, the label and `-0.07` are fine. `1 / displayScale` doesn't
  compile; `1 / UIScreen.main.scale` compiles and parses (section 3.3).
- **Inter, committed:** nothing needs Xcode. Three things go with the download step, and `.gitignore` has to keep ignoring Satoshi (section 4).
- **Dark is mixed from PR 2 to PR 6 and `weekly.yml` would ship that to External.** The user has to hold those approvals (section 5.3).
- **The launch screen is the flash:** `UIColorName` is `Graphite` on every launch (section 6).

## 2. One system: what is in the code

Values live in `Theme.swift`, `Typography.swift` and the colour sets. No site asks which appearance it is in. These are the only new types:

| Type | Where | Why |
| --- | --- | --- |
| `RyftFont`, with `View.font(_: RyftFont)` | `Typography.swift` | A `Font` can't carry tracking or caps, and 711 lines use `.ryft` or `.ryftNumber`. Removing `Font.ryft` keeps those lines compiling and the compiler lists the rest: a prototype failed at 6 sites and `OrbitGaugeTodayTests:430`. It holds font, tracking and caps, with no look and no environment |
| `BandStyle` (`solid`, `half`, `outlined`, `none`) | `Shared/` | A pure function of the score, with `OrbitGaugePalette.highFrom` and `moderateFrom` as the one owner of 67 and 34. The brief's name; `design.md` follows it |
| Hatch `Shape` | `Shared/RyftHatch.swift` | Geometry only. The gauge draws it in the app and the widget |
| `Theme.rule` | `Theme.swift`: `textPrimary.opacity(0.20)` | Plan's soft row rule: 1.61:1 in light, 1.66 in dark. **A computed colour, not a colour set:** a set would add a 24th colour, drift the website and need a widget copy. It also stays visible in today's dark, where `separator` is 8 % |

`Shared/` is synchronized in both targets (ADR 0010), so new files need no Xcode step. The two sites with an outer `.tracking` after a number token, `MetricGauge:161`
and `RyftHeader:26-27`, move into the token: an inner `.tracking` beats an outer one, even at 0. `.textCase(nil)` must not appear in the modifier, because it clears an
inherited uppercase.

**Radii need no call-site change.** PR 2 sets the two numbers; the 56 `cornerRadius: Theme.Metrics.*` lines stay and draw squares. Keep both constants: `tokens.mjs` throws if
either key goes. `Capsule` and literal radii move only where `design.md` lists them.

## 3. The website

### 3.1 `tokens:check`

| Command | Result |
| --- | --- |
| `cd ../plattform/web && RYFT_APP_DIR=.. npm run tokens:check` (the brief) | **False pass.** `RYFT_APP_DIR` resolves against `web/`, so `..` is `plattform`. Prints "Skipping the drift check outside CI", exit 0. With `CI` set, exit 1 |
| `cd ../plattform/web && npm run tokens:check` | Works from the main checkout only: the default `../../app` |
| `RYFT_APP_DIR="$PWD" npm --prefix ../plattform/web run tokens:check` | Works from the app's root and needs no `cd`. In a worktree, give the path to `plattform` |

**That checks the wrong side.** The Mac's `plattform` is on `main`, whose tokens are the old palette, so any Alpine tree reports drift. Check against #143's files, which reads
the platform without touching it:

```sh
tmp=$(mktemp -d)
git -C ../plattform archive origin/web/alpine web/scripts/tokens.mjs web/src/styles | tar -x -C "$tmp"
RYFT_APP_DIR="$PWD" node "$tmp/web/scripts/tokens.mjs" --check
```

`--check` writes nothing: `git status` and every mtime under `web/scripts` and `web/src/styles` were identical before and after these runs. Experiments that needed output
ran on a copy of the script, and scratch held their output.

**What to record in PR 2.** The brief says `tokens:check` stays green. It can't: PR 2 changes values, so the check must report drift until platform regenerates. Record "out of date" as
expected. A thrown "not found" is the failure.

### 3.2 What `tokens.mjs` reads

| Source | Form it needs |
| --- | --- |
| `enum Metrics { }` | `static let name: CGFloat = <digits>`. The block ends at the **first `}`**, the number isn't anchored at its end, and all six keys are required |
| `fileprivate var size` and `weight` | The switch forms of today |
| `func ryftLabelStyle` | The first literal `.tracking(<digits>)` after it |
| `struct Wordmark` | `.tracking(size * <digits>)`, no sign (`tokens.mjs:188` on all three branches) |

### 3.3 Each value, tested

| Form | Result | Do |
| --- | --- | --- |
| `cardRadius = 0`, `tileRadius = 0` | Reads 0, `--card-radius: 0px`. The site's CSS uses neither | As is |
| `hairline: CGFloat = 1 / displayScale` (brief) | Doesn't throw: the regex reads `1`. **Doesn't compile:** `displayScale` is an environment value, and a `static let` can't see it | No |
| `static var hairline: CGFloat { 1 / UIScreen.main.scale }` | **Throws**: `static var` isn't matched and its `}` ends the block | No |
| `static let hairline: CGFloat = 1 / UIScreen.main.scale` | Reads `1`, `--hairline: 1px`, no drift. Type-checks clean, Swift 5, iOS 17 target | The form to use if the value changes |
| Label `.tracking(size * 0.08)` | **Throws** | No |
| Label `.tracking(0.88)` | Reads `0.08em` (0.88 / 11) | Use it, with a comment |
| Wordmark `.tracking(size * -0.04)` | **Throws** | Needs platform |
| `.font(.ryftNumber(size: size, weight: .bold).tracking(size * -0.04))` | Parses once the regex takes a minus. Output `-0.04em` | Use it: the tracking has to be inside the token, because a `ryftNumber` of 32 pt carries its own -0.07 |
| Display `-0.07` | Not read at all | Free |
| Weights `.bold` and `.regular` in the `weight` switch | Seven lines change. `--type-*-weight` is used only by the styleguide | As is |

**Should `hairline` change at all?** `1 / displayScale` is one device pixel, 0.33 pt on a 3x phone. The brief's own decision is "1 pt ink rules", ADR 0015 says 1 pt, and the site
draws 1 CSS px, which is three device pixels on the same phone. So the brief's value makes the app's rule a third of the site's. **I recommend leaving `hairline = 1`.** That is
ui-designer's call; either way the site stays at `1px`.

No comment or positive-number trick avoids the wordmark change: it would generate a wrong value. The site doesn't read `--tracking-wordmark` (`Brand.module.css:5` hardcodes `-0.04em`).

### 3.4 What platform must change

We don't edit `../plattform`; head-architect relays this. Two facts make the brief's "remove `ref:` at the end" too late:

- `delete_branch_on_merge` is on, and #142 and #143 both pin `ref: design/alpine-light-palette`. Merging #100 deletes it and their checkout fails.
- Platform `main` has no `ref:`, so it follows app `main`. Verified: main's tokens against #100's tree, `CI=1`, exit 1. Every push to platform `main` and every web PR goes red at PR 1.

| # | When | Change |
| --- | --- | --- |
| P1 | **Before PR 1 merges** | Pin the app checkout to a SHA in `.github/workflows/ci.yml`: platform `main` to current app `main`; #142 and #143 to #100's head. After PR 1 merges, move the web branches to its squash commit |
| P2 | Before PR 2 merges; safe now | `tokens.mjs:188`: `([\d.]+)` becomes `(-?[\d.]+)`. No output change at `0.32`. Without it the next regeneration throws |
| P3 | After PR 2 merges | Move `ref:` to PR 2's squash commit, `npm run tokens`, commit. Diff: radii 0, seven weights, `--tracking-label: 0.08em`, `--tracking-wordmark: -0.04em` |
| P4 | After PR 6 merges | Move `ref:`, `npm run tokens`: `tokens.json` only, since #143's `tokens.css` is light. Then remove `ref:` |

PR 1 and PR 3 to PR 5 change no value it reads, if no colour set is added; `hairline` stays `1`. `tests/contrast.test.ts` reads the light column only, so PR 6's dark values can't fail it.
`tests/mark.test.ts` reads `design/ryft-mark.svg`, which doesn't change.

Optional: when `RYFT_APP_DIR` is set and wrong, `tokens.mjs:27` should fail rather than skip. That skip is what hid the brief's mistake.

## 4. Fonts

Inter replaces Satoshi. From `Inter-4.1.zip`, already verified: `extras/otf/Inter-Regular.otf` and `Inter-Bold.otf`, PostScript names `Inter-Regular` and `Inter-Bold`, 1.24 MB, licence SHA-256
starts `262481e8` as on the web. **The Medium mapping:** `postScriptName(for:)` sends `.medium`, `.semibold`, `.bold`, `.heavy` and `.black` to `Inter-Bold` and everything else to `Inter-Regular`.
The `weight` table says `.bold` outright, or the site reads 500. `ryftNumber`'s default becomes `.bold`: 34 of 37 sites take the default. Three `.fontWeight` sites remain;
`StatusViews:289` asks for a medium that no longer exists, so check it.

All in PR 2:

| Place | Change |
| --- | --- |
| `Ryft/Resources/Fonts/` | Add the two OTFs and `Inter-OFL.txt`. The name avoids a clash, because resources land flat in the bundle. The OFL wants the licence shipped with the font |
| `.gitignore:10-13` | `*.otf` and `*.ttf` would hide the new files. **Replace with `Ryft/Resources/Fonts/Satoshi-*`:** every Mac still has the old files on disk, and a broad `git add` would otherwise commit them against ITF FFL section 02 |
| `Ryft/Info.plist:90-92` | Two rows for three. Allowed: it isn't the pbxproj or entitlements |
| `scripts/fetch-fonts.sh` | Fetches Inter, per the brief, and checks the SHA-256. It becomes the upgrade tool, run by hand with `make fonts` |
| `.github/actions/setup/action.yml` | **Delete the Fonts step**, fix the description. A committed file needs no download, and each job would fetch a GitHub release and overwrite tracked files. A failed `curl` fails the job |
| `ci_scripts/ci_post_clone.sh:11` | Delete that line and the comment's Satoshi part. Xcode Cloud then runs config only |
| `Makefile:114-115` | Delete the archive check: the files are in git, and the face test below runs on every PR |
| `RyftFonts`, `Font.ryft` | Delete `isAvailable` and the SF Pro Rounded fallback. Nothing can reach it now |
| `LicensesView:28` | The row becomes Inter, SIL OFL 1.1, The Inter Project Authors |
| Text | `README.md:32,161-163`, `docs/APP_STORE.md:89`, `check-shared-types.py:7`, comments in `MetricGauge:5`, `WidgetOrbitGauge:2`, `HealthPermissionView:970`, `Typography:1` |

**Xcode: nothing.** `Ryft/` is synchronized, and the pbxproj doesn't name Satoshi. New test: `UIFont(name:)` is non-nil for both faces.

**Widgets stay on the system face.** Inter there needs the files in `RyftWidgets/` and a `UIAppFonts` row in its `Info.plist`, also without Xcode, for another 1.2 MB. The brief doesn't ask for it.

Layout, measured from the files: line box 1.350 to **1.210 em**, so text-hugging rows are about 10 % shorter; x-height 0.484 to 0.546; text about 8 to 10 % wider. Section 7 lists what that touches.

## 5. Sequence

### 5.1 PR 1, the smallest honest version

Tests alone can't turn #100 green. `Alert` and `Accent` are both `#000000` in light, so past the band and inside it are the same pixels, and high and low are the same ring. ADR 0015 warned that
this should ship with the band logic.

`design.md` 3.1 proposes disabling `midGlide` and shipping a one-level ring with an invisible past-the-band. **I don't take that.** It disables a test and ships a gauge that can't show its own
states, in a build `main` calls releasable. **PR 1 takes the gauge's two cues from PR 3 instead.** The drawing has one place for each:
`OrbitGaugeDrawing:161` for the ring and `OrbitStrainArc`'s `past` for the arc. `Shared/` carries both to the widget.

| Pin | Change in PR 1 | New assertion |
| --- | --- | --- |
| `theWarmUpMark` | The W is `textSecondary` | `>= 4.5` in both appearances |
| `theRailsOpacityIsPinned...` | `bandRailOpacity = 1` | Ink `>= 3`; the "sub-3:1 on purpose" claim goes |
| `pendingOpacityIsPinned...` | Stays 0.6, Sleep in ink while pending (`design.md` 3) | Test renamed. Its claim was false: 5.74, not `< 3` |
| `arcsAndDotsReachThreeToOne...` | Ring by `BandStyle`: solid, dashed, outlined, all ink | `moderate` leaves the list as a colour: every level is ink `>= 3` |
| `theColourPastTheBand...` | Past the band is the hatch; `strainPastBand` leaves the palette | Tone tests, plus the ink `>= 3` on track and background |
| `midGlide...NeverAlert` | The same hatch | Ink coverage per `design.md` 3, still rendered |

Plus:

- `git merge origin/main`: #100 is four commits behind and not rebased, and force-push is forbidden.
- `make mark-svg`: SVG only, so the shipped icon PNGs wait for PR 5. The 7 widget colour sets from `check-shared-types.py`.
- `BandStyle` tests at `(66, 67)`, `(33, 34)`, `nil`.
- ADR 0015 and ADR 0017 (section 9), CHANGELOG.

**About 250 lines plus tests, an estimate.** Dark also gets the ring shapes and hatch, in its existing colours. **The six is from `abbcb82`:** main's Focused tests have never run against this palette, so
the first push after the merge may show more.

### 5.2 The six

| PR | Scope | Light | Dark | Website |
| --- | --- | --- | --- | --- |
| 1 | Section 5.1. **P1 first** | Monochrome; gauge by shape. Tiles, zones, stages and severity by tint, each with a number or word | Ring shapes and hatch, in hue | No value changes |
| 2 | `RyftFont`, section 4, radii, wordmark, label, `Theme.rule`, surfaces, buttons, catalog. **P2 first** | Inter, square | **Mixed starts:** Inter, square, old colours | Drift expected, then P3 |
| 3 | `ScoreRing`, `MetricGauge`, tiles, `Theme.band`, zones, stages, charts, severity, destructive, polarity arrows, hairline rail and pending | Every scale reads in greyscale | Shapes, in hue | None |
| 4 | Today, Sleep, Strain, widgets, Live Activities, `Brand.*`, `NotificationRing` (section 6) | Done for these | Mixed | None |
| 5 | Train, Insights, Profile, onboarding, hero, icon. **Welcome, auth and `MisconfiguredBuildView` stop forcing dark** | Done | Welcome shows the mixed dark | None |
| 6 | Dark colour sets, the flip (section 6), `CLAUDE.md`, ADR status. **P4 after** | The default | The inversion | P4 |

### 5.3 The window

- **PR 1 to PR 5 are seen in full only by people who chose Light, or System on a light phone.** Default-dark testers see PR 1's gauge shapes, then the mixed look from PR 2. Say so in each CHANGELOG line.
- **Mixed means more than fonts.** From PR 2, cards lose their fill while `separator` is still 8 % in dark, so hierarchy is weak until PR 6. `plan.md` accepts this, but "nobody lands on a half-done look" is
  true only of the flip.
- **Hold External.** `weekly.yml` sends the newest build to External on Mondays, with an approval per run on `external-testflight`, and `plan.md` merges the six in order. Decline those runs from PR 2 until PR 6, and
  run no `make release` in between. Nightly to Internal can go on. **This needs the user's agreement.** A long-lived branch is forbidden, and type and shape can't sit behind a flag without a second look.

## 6. The default flip

Plan puts Welcome and auth in **PR 5**, so PR 6's list is shorter than the brief's.

**PR 5:** drop `WelcomeView:27`, `AuthComponents:62` **and `:63`** (`toolbarColorScheme`), `PlatformConfig:77-78` (Graphite and forced dark, Release only). The Apple button (`AuthComponents:269`, `AppleSignInButton:16`)
reads the scheme and follows.

**PR 6:**

1. `Settings.swift:99`: `?? .dark` becomes `?? .light`. **No migration, as plan says.** `didSet` doesn't run in `init`, so nothing writes a default; the key is written only by the picker
   (`ProfileView:604`) and survives log-out (`Settings:138`). Nil follows the default; a stored `dark` stays. Test with `Settings(defaults:)` on an empty suite: nil to `.light`, `"dark"` to `.dark`, `"system"` to `.system`.
2. `Ryft/Info.plist:103`: `UIColorName` `Graphite` becomes `Background`.
3. Colour sets in **both** catalogs; `check-shared-types.py` compares them. `make mark-svg`, because the dark icon SVG reads those sets, then `make icon`.
4. Delete the branches: `FocusedRowInk:10,16` (light's branch wins, drop the `scheme` parameter), `ExerciseCard:241` (both arms are equal today), `SourceBadge:33`.
5. `CLAUDE.md:19`, `.claude/skills/ryft-app-conventions/SKILL.md:47`, `docs/APP_STORE.md:113`, stale comments at `RyftApp:878` and `:400,:409`.

**What could flash dark:**

| Where | Today | After | What's left |
| --- | --- | --- | --- |
| **Launch screen** | `Graphite` for everyone, every launch: a near-black frame before a white app | `Background` | It follows the **system**, because it can't read the app's setting. App light on a dark phone: black, then white. Accepted. `UIUserInterfaceStyle` in `Info.plist` would break `.system`. iOS caches this image: check on a device |
| First SwiftUI frame | `Settings` is read in `App.init`, `preferredColorScheme` at `RyftApp:146` | Same | Not verified that frame one has it. Check on a dark phone |
| `SplashView` | Reads `Theme`, **not forced** | No change | None |
| Welcome, auth | Forced dark | Dropped in PR 5 | None |
| Tab bar proxies | Trait-aware `UIColor` | No change | None |

**Widgets and Live Activities (PR 4):**

- Both follow the system, not the app's setting, so an app in light on a dark phone has dark widgets. That is true in reverse today. Not a flash.
- `Brand.background` and `Brand.ink` are Mist and Graphite, not paper and ink.
- **Live Activities are always dark:** `activityBackgroundTint(Brand.graphite)` at `RyftWidgets:25-26` and `WakeAlarmLiveActivity:14-15`, plus `.background(Brand.graphite)` at `:62`.
- **Dynamic Island must stay fixed white.** It is always black, so an adaptive ink is black on black in light.
- `Brand.teal` is in both activities and `ReadinessWidget:219`.
- `NotificationRing` hardcodes dark's hues because its extension can't read the catalog; it also doesn't compile `Shared/`, so it holds the thresholds a second time.

**UI tests** pass `-appearance dark` explicitly, as does `screenshots.sh`, so the flip won't touch them and none covers the default. The `Settings` test is what does.

## 7. What must be re-measured

Computed from the colour sets, WCAG luminance, gamma sRGB compositing; dark is the brief's table. Nothing was rendered. The contrast tests loop both styles, so PR 6 re-runs them.

| Where | Claim today | Light | Dark after PR 6 | Do |
| --- | --- | --- | --- | --- |
| `FocusedRowInk:7-8` | Grey on the tint 4.51 | `textSecondary` 5.74, `textTertiary` **4.49** | 9.03, 6.04 | Keep the dash out of tertiary on the tint. Rewrite the comment |
| `FocusedRowInk:14-16` | Outline 4.7 | 4.76 | Today's `surfaceRaised` would be 1.27; light's branch gives 6.27 | Delete the branch |
| `FocusedRowInk:19` | Tertiary 4.40 on the raised field | 4.55 | 5.87 | Number |
| `FocusedRowInk:3-5` | Names `FocusedRowInkTests` | Those are in `FocusedPolishTests` | | Fix |
| `ExerciseCard:233` | `warning` as text | 3.45, 2.75 on the tint | 4.89, 4.08 | PR 1 |
| `ExerciseCard:238` | Field on the tint 1.01 and 1.28 | 1.05 and 1.25 | Re-compute | Number; PR 2 adds the edge |
| Focused `design.md` 2.2, 2.3, 2.8, 5.1 | Contrast tables | Superseded | | A note at the top, no rewrite |
| Focused `design.md` 5.1, Dynamic Type | Satoshi | Inter 8 to 10 % wider: "102.5" 86 to about 93 pt in a 100 pt field at 320 and AX3 | Same | **Re-measure in PR 2:** now in both appearances |
| Row heights | Satoshi's line box | About 10 % shorter | Same | Hit areas `>= 44` in PR 2 |
| `orbit-gauge/design.md` 109, 194, 280 | Hue columns | History | | Pointer only |
| ADR 0015, Consequences | Secondary 5.9 | 6.20 | | PR 1 |
| `Theme.swift` comments | Teal, green to red | True of dark until PR 6 | | PR 6 |

Dark's steps: the track is 1.27, Warning 3.84 on it, and the arcs all pass 3:1. REM is 2.56 and Awake 1.39 on black, the same shape as light's 2.05 and 1.32, so the swatch edge does the work in both.

| Test | Today | When |
| --- | --- | --- |
| The six pins | Red | PR 1 |
| `OrbitGaugeTodayTests.inTheApp` | Centre slot holds "100" at 0.6 and "71"; Inter Bold digits are wider, and `:430` stops compiling | **Measure in PR 2** |
| `FocusedPolishHostedTests` fit tests | Pass, silently on Inter | Add 320 and AX3 in PR 2 |
| `EnvironmentTests:3191-3194`, `widestWord` | Measure the font | Follow Inter; check German caps in PR 2 |
| `FocusedPolishTests` light contrast | Pass; comments quote old numbers | Update in PR 2 |
| Orbit render tests with a default environment | Default is light | State the scheme in PR 1 |

**`make test`** runs `config`, then `xcodebuild -scheme Ryft -testPlan Unit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`. So: Unit only, no `UISmoke`, no `Full`, no lint. **This Mac has no available simulator with that
name**, so it should fail here to find a destination; I didn't run it. CI doesn't use it: `ios.yml` has its own steps through `ci-simulator.sh`, including `UISmoke`. The brief's "done when" should read "CI green", not "`make test`".

## 8. The brief's rules

- **"No shadow, no `LinearGradient` in `Design/`: grep and remove."** There is nothing to remove. No `.shadow(` exists in `Ryft`, `RyftWidgets` or `Shared`. `bar.shadowColor` at `RyftApp:413` is UIKit's tab bar line.
- **The 2 `LinearGradient`s are both in Train's session, and one is the focused fade.** `FocusedSessionView:163`: rows scroll under the strip through a fade of `Theme.background`. `ExercisePage:228`: a 16 pt mask on a horizontally scrolling row.
  Neither paints a colour; both fade content out. The brief's rule doesn't reach them, though its decision says "no gradients". **I recommend keeping both** and ui-designer deciding: removing them means a hard cut in the middle of a set.
- **The "test" should be lint.** A unit test can't see the sources on a simulator without `#filePath` tricks. Add `scripts/check-design-rules.py` to `make lint`, as `check-shared-types.py` is, from PR 2: `.shadow(`, `Gradient`, `Theme.teal` in `Ryft/Design`, and from PR 4 `Brand.teal` in
  `RyftWidgets`, which the brief's wording would miss.
- **"Snapshot-free" holds as "no reference images".** None exists; the shot suites write PNGs for people, behind an environment variable. New level tests assert `BandStyle`. **It can't mean no rendering:** `midGlide` is a property of the drawing mid-entrance and has no value to assert, and 12 test files render today.
- **`BandStyle` "in both appearances"** adds nothing: it's a pure function of the score. One test at the boundaries; the contrast tests cover both styles.

## 9. ADRs

- **ADR 0015** reaches `main` with PR 1. Correct its Consequences there: the gauge ships with the palette, and the other scales follow in PR 3.
- **ADR 0017, "Dark is the inversion": PR 1 adds it,** rather than PR 6. PR 2 is the first change that needs it, since it moves dark on purpose and deletes Satoshi, and review should have the reason. PR 1 carries 0015, so 0017 can link it. PR 6 marks 0015 and 0017 complete.
- **ADR 0016** is reserved: its text is in `docs/work/2026-11-05-wipe-recovery/design.md`, and no file is on `main` yet. 0017 must not link it.

## 10. What could go wrong

| Risk | Response |
| --- | --- |
| PR 1 merges before P1 | Platform CI goes red and #142, #143 can't check out. Make P1 a merge gate; the branch can be restored |
| PR 1's hatch takes longer than the pins | Fall back to `withKnownIssue` naming PR 3, not `.disabled`: the test still runs and fails when fixed. It leaves the gauge flaw, so tell the user |
| The hatch on a tinted or clear widget | Not verified. Validate in PR 1 |
| `textCase` caps on user text, or `ß` in German caps | ui-validator, PR 2 |
| A new colour set | Drifts the site in a PR this note calls clean. `check-shared-types.py` doesn't catch it. Reviewers should ask |
| `Metrics` gains a brace, or loses a key | `tokens.mjs` throws on the next regeneration. Section 3.2 |
| Stale launch image after the update | Device check in PR 6. Known iOS behaviour |

## 11. Other things in the brief that aren't so

- **"PR #100, rebased on `main`":** neither. It's behind `main`, and the merge of `main` in the Alpine worktree isn't pushed.
- **"Light is done (ADR 0015)":** the widget's 7 colour sets aren't.
- **PR 6 "should be colour sets, the icon's dark variant and a validation pass" because "every component already reads tokens":** section 6 lists what doesn't. Most of it moves to PR 4 and PR 5, so it holds only if those PRs do it.
- **"Exact inversion":** the brief's table isn't arithmetic. Six values differ from `255 - x` by up to 11 levels (`SurfaceRaised` `#1F` against `#14`). Use the table: plan points at it and its dark contrast is better. Say "inversion", not "exact".
- **"The app follows it exactly":** the site's soft rule is 14 %, plan's is 0.20. Plan wins.
- **`design.md` must follow two calls here:** `BandStyle` and `Theme.rule` as a computed colour, not a `Rule` colour set.
