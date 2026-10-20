# Security

RYFT handles health data (heart rate, HRV, sleep, workouts) for real people.
Please report anything that could expose it privately, never in a public issue.

## Reporting

- Use GitHub's **private vulnerability reporting**: the repository's Security tab →
  Report a vulnerability. Or email `security@ryftapp.de`.
- Include what you found, how to reproduce it, and which build (Profile → About shows
  the version and build).
- You'll get an answer within 72 hours. Please give us time to fix the issue before
  you disclose it.

## Scope

- This app (iOS), including how it stores data on the device (SwiftData, Keychain) and
  talks to the platform.
- The platform (`api.ryftapp.de`) has its own repository; reports about it are welcome
  through the same channels.

## What is public on purpose

`Config/Production.xcconfig` contains the API URL, the Supabase project URL and its
**publishable** key. These are designed to be public: the platform's row-level
security and revoked grants mean that key exposes nothing. Secrets (App Store Connect
API key, signing) live only in GitHub environment secrets and never in the repository.
