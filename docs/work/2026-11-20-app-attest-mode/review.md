# Review: X-RYFT-App-Build and the App Attest mode (2026-11-20)

Commits reviewed: 1bedc2e (implementation). Tests: ccbfd15 (30 tests, three runs green).

## code-reviewer
- **Should-fix:** plan.md criterion 9 said an account switch forgets the mode; the design (and code) publish the new
  side's cached mode or absent. **Fixed** in plan.md; the test follows the corrected wording.
- **Nit:** `FlagStore.reload()` republished the same cached answer on every account/demo switch, ending a `403` lift on
  an answer that didn't come with a token. **Fixed:** `publishAppAttest` publishes only when the mode or its fetch
  time changed.
- **Nit:** the "once per change" comment was wrong. **Fixed** with the change above.
- **Nit:** `RemoteConfig.appAttest` lacked `= nil`. **Fixed.**

## security-privacy-reviewer
No blocking or should-fix findings.
- Nit: the 24 h `offTrust` isn't tied to `ttl_sec`; the only effect is extra `missing` warn lines under `warn`.
  Accepted.
- Nit: the build reaches the platform's logs linked to the account via `request_id`. Not new data (URLSession's
  default `User-Agent` already carries `CFBundleVersion`); the App Privacy label doesn't change. **For the user:** name
  the build header in the App Attest paragraph of ryftlab.de/privacy (C2).
