# Review: domain ryftlab.de (2026-11-14)

Reviewers (read-only, in parallel): code-reviewer, security-privacy-reviewer. No blocking findings.

## code-reviewer
**Verified sound:**
- The host constants and checks moved together:
  - `AppRoute.host` with `www.`;
  - `WebContentSource.host`, `allows` and the redirect delegate;
  - `anyHelpHost`, `LegalPage.init?(url:)`, `universalRedirectURL`, `Production.xcconfig`.
- `redirectURL` stays `ryft://auth/callback`.
- The catalog: 3 keys renamed in place, each equal to its `Text` literal.
- The negative tests (`www.`/`evil.`, port, `http`, `.example.com`, foreign redirect) are intact.
- No entitlements, pbxproj or `Models.swift` changes.

**Findings:**
- **Should-fix:** the demo account is renamed to `review@ryftlab.de` before the platform seeds it.
  → Kept as the target state, because an old-domain account can be taken over (security #3). The STATUS entry now says to fill App Store Connect only after `seed_demo.sh` seeds it.
- **Nit:** STATUS said "older entries below name the old domain", which wasn't accurate.
  → Fixed: it now names the dated entry and the `docs/work/` folders.
- **Nit:** `.claude/agents/security-privacy-reviewer.md:39` still names the old domain.
  → It can't be edited from a session (agent definitions are protected). It goes with the next fleet-config PR.

## security-privacy-reviewer
**Verified sound:**
- No old host in code, config, `Info.plist`, `PrivacyInfo.xcprivacy`, entitlements, tests or scripts.
- Every allowlist is exact-host. ATS has no Release exceptions, and Associated Domains is absent.
- Old saved data fails closed.

**Findings:**
1. **High (operational):** builds already out call the old `api.` host with tokens and health data, and a lapsed domain could be re-registered.
   → In the STATUS "Your steps": keep it registered until those builds expire, no `api.` record, null MX, DMARC reject, expire the old builds.
2. **High (operational):** a Supabase redirect URL left on the old domain.
   → STATUS now says to delete every one of them explicitly.
3. **Medium:** Supabase accounts on old-domain addresses.
   → In STATUS: delete them or move them.
4. **Low:** no test that the old host is rejected.
   → **Not done, on purpose.** The brief's done check is that `ryftapp` appears nowhere in tests. Any other host is already rejected by the exact-host tests.
5. **Low, Debug only:** a saved `dev.apiURL` override on development phones may still point at the old host.
   → Noted for whoever tests on a dev phone: Profile → Developer → clear the override.
- **AWS → GCP:** `docs/APP_STORE.md:47,156` still names AWS eu-central-1 as the processor. Not blocking this PR. The privacy policy and those lines change before GCP serves production data.

## Not run
- **ui-validator:** the only visible change is `ryftapp.de/support` → `ryftlab.de/support` in a caption, the same length. Layout is unchanged.
- **performance-profiler:** no sync, launch, list or chart change.
