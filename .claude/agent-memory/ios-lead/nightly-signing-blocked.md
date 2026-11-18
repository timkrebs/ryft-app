---
name: nightly-signing-blocked
description: Since 2026-11-05 the nightly TestFlight archive fails on Apple signing (certificate limit, then an unsigned Program License Agreement), so no build/* tag after 20261101.071450
metadata:
  type: project
---

No nightly has uploaded since `build/20261101.071450`. Every run since 2026-11-05 has failed in "Archive and upload" with exit code 65:
- **2026-11-05 to 11-08:** "Your account has reached the maximum number of certificates". Cloud signing on the hosted runner couldn't create a development certificate.
- **2026-11-14:** "PLA Update available … the Account Holder must agree to the latest Program License Agreement".
- Both end in "No profiles for 'dev.timkrebs.ryft' / '…RyftWidgets'".
- There were no nightly runs between 11-09 and 11-13.

**Why:** only the Account Holder (the user) can fix either one in the Apple Developer account. The PLA is accepted on developer.apple.com → Account. The certificate limit means revoking unused Apple Development certificates. Until then, merging to `main` ships nothing, whatever the brief says about the nightly.

**How to apply:**
- Before telling the user a merge "ships tonight", check `gh run list --workflow nightly.yml --limit 3`. If it's still red, the PLA/certificate fix comes first.
- After his fix, a manual `nightly.yml` run is his call (`gh workflow run` needs approval).

See [[headless-permission-preflight]].
