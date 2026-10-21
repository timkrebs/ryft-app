#if canImport(AlarmKit)
import AlarmKit

/// Keep identical to `WakeAlarmMetadata` in `Ryft/Features/Sleep/SleepPlannerViewModel.swift`:
/// the wake alarm's snooze countdown is rendered here from the app's `AlarmAttributes`.
@available(iOS 26.0, *)
struct WakeAlarmMetadata: AlarmMetadata {}
#endif
