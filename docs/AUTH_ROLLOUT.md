# Apple and Google sign-in rollout

`RYFT_AUTH_ENTRY` is a build setting. Set it in the isolated candidate's Debug or Release xcconfig for validation.

| Setting | Welcome and account access |
| --- | --- |
| `legacy`, unset, or unrecognized | Existing Sign in with Apple and email access. Google stays hidden. |
| `transition` | Adds Google and leaves legacy email access available. Existing users can add Apple or Google under **Profile → Account → Sign-in methods** after signing in. |
| `social` | Shows Apple and Google in Welcome. Email entry, password recovery callbacks and change-password UI are hidden in this build. Keep the previous build and an approved legacy access plan until support and the reviewer account can use the new entry points. |

Google uses the pinned Supabase Swift SDK's authorization-code PKCE flow through the system authentication session. Allow the exact `ryft://auth/oauth/callback` URL in the intended Supabase project. Existing email confirmation and recovery keep `ryft://auth/callback` during transition. Configure the Google Web OAuth client with that Supabase project's HTTPS `/auth/v1/callback` URL as the redirect. Store the Google client secret only in the approved server-side configuration. Keep the existing native Apple capability and Supabase configuration.

Enable Supabase manual identity linking in the approved test environment before exercising **Add Google sign-in**. The linking request is authenticated by the current Supabase session and the App checks the original account before exchanging the callback. Signing in while signed out uses Supabase's provider behavior, including its documented verified-email automatic linking. RYFT does not match email addresses, merge accounts, or delete older credentials in the App.

Before selecting `social` for a release build, verify the hosted settings with dedicated accounts. Check new Apple and Google sign-in, cancellation and retry, expired credentials, account switching during a pending link, and a Google identity already linked to a different account. Sign in to a legacy email account first, add a provider, sign out, and use that provider to verify the original account UUID and data are retained. Confirm the supported recovery path and App Review credentials. Do not disable legacy sign-in at the Supabase project until the transition is complete and approved.

Signed-out support opens the existing support mailbox with an empty message. Signed-in feedback only attaches diagnostics when the user opts in.

[Google provider setup](https://supabase.com/docs/guides/auth/social-login/auth-google) · [Supabase identity linking](https://supabase.com/docs/guides/auth/auth-identity-linking) · [Supabase redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls)
