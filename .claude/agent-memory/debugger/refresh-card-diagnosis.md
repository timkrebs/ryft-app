---
name: refresh-card-diagnosis
description: How the Today "Couldn't refresh just now" card is produced and what its Details button reveals
metadata:
  type: project
---
The card's Details button exists only for APIError.http (AppState.errorDetails = diagnosticDetails); transport errors (timeout, URLError.cancelled) and CancellationError give a card with "Try again" only. Transport failures are also never recorded in APIStatus.requests, so Copy diagnostics can't show them.
**How to apply:** when a tester's screenshot shows the card without Details, suspect cancellation/timeout/decoding, not 429/503. Fault seam: DEBUG `-RyftFault "/v1/me=timeout"` (MockPlatformAPI.faults) on branch debug/refresh-repro.
