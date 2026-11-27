# Direct wearable connections on iPhone

## Install locally

1. Connect and unlock the iPhone. Tap **Trust** if prompted and enable **Developer Mode** under **Settings → Privacy & Security**. Complete the restart and device confirmation if prompted.
2. From the RYFT workspace, run:

   ```bash
   cd app
   make config
   open Ryft.xcodeproj
   ```

3. In Xcode, select the **Ryft** scheme. Under **Product → Scheme → Edit Scheme → Run**, keep **Debug**. Select your iPhone as the run destination. Under **Signing & Capabilities**, use the existing development team and automatic signing. The app uses bundle ID `dev.timkrebs.ryft` and the existing HealthKit capability.
4. In **Edit Scheme → Run → Arguments**, add `-RyftFlags` and `devices.setup` as two launch arguments. The existing Devices & sync page uses this Debug override while the production flag is unset.
5. Verify your local Debug configuration points at `https://api.ryftlab.de` and `https://ingest.ryftlab.de`. Run with **⌘R**. Use a designated RYFT beta test account with current health-data consent. Turn off Demo data when checking the production API.

## Test against the current production rollout

- On a fresh test account, choose Garmin or Suunto in **What do you wear?** and tap **Continue**. **Connect your tracker** shows the selected vendors and their availability. Continue proceeds to Apple Health setup. Returning to the picker keeps the selection, and **Profile → Devices & sync** lets the user connect later.
- Sign in and open Recovery, Sleep and Strain. Use a normal HealthKit sync and check that a new eligible measurement appears once.
- Open **Profile → Devices & sync → Direct connections**. Garmin and Suunto should show **Coming soon**. Their detail pages should have no account-link action. Apple Health access and **Check sync** belong to the same Devices & sync page.
- Background and reopen the app. Pull the device offline while on a provider detail page. Verify that the last loaded status stays visible and connection actions are disabled. Restore connectivity and refresh the status.
- Switch RYFT accounts or sign out and back in. Verify that the preceding account's provider status is cleared. Reopen the app to check the production availability again.
- Increase Dynamic Type, turn on VoiceOver, and verify navigation, provider names, status labels and action descriptions.

## Test after each provider is approved and enabled

On **Connect your tracker**, tap the selected provider's sign-in action. RYFT opens the provider's page in the system authorization browser. For two selected providers, authorize each account separately.

Use an approved partner test account and a RYFT test account. Exercise authorization cancellation, account switch while authorizing, expired authorization, and an app restart during authorization. On a successful attempt, verify the app waits for Platform confirmation, shows the granted data types, then displays the latest data time after a real delivery. Check that the same exercise arriving directly and through HealthKit counts once.

On the provider detail page, cancel the disconnect prompt once. Confirm it on the next attempt. Verify that RYFT stops processing new direct deliveries and removes the provider's direct records while copies synced independently through Apple Health remain available. Check the provider's grant screen if the app reports revocation pending.

**Refresh status** rereads the server. The current Platform contract exposes a data receipt timestamp and no direct manual sync action.

## Local provider checks

### Garmin on iPhone

Install the Debug build as described above. Connect the Mac and iPhone to the same Wi-Fi. From the workspace root, start the local test API.

```bash
ryft_garmin_ip=$(ipconfig getifaddr en0)
python3 plattform/scripts/wearable-smoke.py garmin --serve "$ryft_garmin_ip"
```

If Wi-Fi uses a different interface, substitute the Mac's Wi-Fi IPv4 address. Enter your Garmin Personal API key at the hidden terminal prompt. Keep the process running and copy the pairing link to the iPhone.

Open **Profile → Devices & sync → Garmin local test**, paste the link, and tap **Fetch Garmin data**. Allow Local Network access if iOS prompts. **Local API verified** shows up to five recent activities from your Garmin account. This read-only preview keeps the key on the Mac and sends no Garmin data to the production API. Stop the local API with Control-C when finished. The pairing link expires after 30 minutes.

If RYFT cannot reach the Mac, check **Settings → Privacy & Security → Local Network → RYFT** and verify that both devices are on the same Wi-Fi. If the app reports a certificate or pairing error, paste a fresh link from the running terminal session. If the Mac reports a Garmin error, the terminal shows the upstream HTTP status.

When the phone cannot reach the Mac over Wi-Fi, connect the unlocked iPhone to the same Mac with a USB cable. Use the device name shown by `xcrun devicectl list devices`.

```bash
python3 plattform/scripts/wearable-smoke.py garmin --usb-device "Your iPhone"
```

Enter your Personal API key at the hidden prompt. Tap **Load USB preview** in **Garmin local test**. RYFT reads the same activity summary and removes the temporary copy once opened.

### Provider checks from the Mac

From the workspace root, test the Garmin Personal API with one activity list request.

```bash
python3 plattform/scripts/wearable-smoke.py garmin
```

The terminal prompts for your Personal API key without echoing it. The check reports the number of activities in the test page. Register a Garmin Business app with Starter Access for the multi-user OAuth integration. Add Activity or Health access according to the feeds RYFT will read. [Garmin Personal API FAQ](https://developer.garmin.com/gc-developer-program/personal/personal-faq) · [Garmin Developer Program](https://developer.garmin.com/gc-developer-program/overview/)

For Suunto, request partner access and subscribe to the Developer API. In the test app's API Zone OAuth settings, set the redirect to `http://127.0.0.1:8765/callback` if accepted. Run the following from the workspace root and authorize your Suunto test user in the browser. The terminal prompts for the client credentials and subscription key.

```bash
python3 plattform/scripts/wearable-smoke.py suunto
```

If the portal requires an HTTPS redirect, use the provider's API Zone test flow with an approved test callback. [Suunto partner program](https://www.suunto.com/partners/welcome-partners/) · [Suunto API Zone setup](https://apizone.suunto.com/how-to-start)

These checks talk to the providers from the Mac and keep tokens in memory. The production app redirects are `https://api.ryftlab.de/v1/connect/garmin/callback` and `https://api.ryftlab.de/v1/connect/suunto/callback`. Activate those clients only after the real server adapters and a signed end-to-end delivery have been verified. Use the Suunto Notification Secret to verify webhook signatures. [Suunto webhook guide](https://apizone.suunto.com/webhooks)
