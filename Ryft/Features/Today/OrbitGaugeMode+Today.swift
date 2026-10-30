// The one mapping from Today's decision to the orbit (architecture.md §3). `TodayContent.orbit` calls it, and
// `ReadinessSnapshot.make` writes what it needs, so the widget draws the same mode from the snapshot
// (`ReadinessSnapshot.gauge`). `TodayView` never maps. The scores always come from `p.tiles`: gauge and tiles show
// one day.
import Foundation

extension OrbitGaugeMode {
    /// | Path | `p.gauge` / note | Mode |
    /// | A, N1, L-B + r, L-D | `.readiness(r)` | `.scored(v)`, v of the tiles' day |
    /// | S2 | `.readiness(r)`, `.learning(prog)` | `.scored(v, learning: prog.nights, counted)` |
    /// | N2 | `.readiness(nil)`, `.blocked` | `.scored(v)` without readiness: hollow dots where the day has none |
    /// | S1, L-B short | `.baselines(n)` | `.calibrating(n, counted)` |
    /// | L-B long | `.baselines(n)`, `.needsVitals` | `.calibrating(n, .heartRateNights)` |
    /// | C | `.pending` | `.pending(previous: v of the latest scored day)` |
    /// | E | `.firstImport` | `.scored(.empty)` (the import card covers the import itself) |
    init(_ p: TodayPresentation) {
        switch p.gauge {
        case .readiness(let readiness):
            var learning: OrbitGaugeCalibration?
            if case .learning(let progress) = p.note {
                learning = OrbitGaugeCalibration(nights: progress.nights, signal: Self.counted(p.note))
            }
            self = .scored(OrbitGaugeValues(p.tiles, readiness: readiness), learning: learning)
        case .baselines(let nights):
            self = .calibrating(OrbitGaugeCalibration(nights: nights, signal: Self.counted(p.note)))
        case .pending:
            // The tiles show the latest scored day here; its readiness is the dimmed one.
            self = .pending(previous: p.tiles.source.map { OrbitGaugeValues(p.tiles, readiness: $0.readiness) })
        case .firstImport:
            self = .scored(.empty)
        }
    }

    /// What a baselines count counts: the heart-rate nights over a long history without them (path L), the one
    /// signal that fills while the other is absent (F3), else any night with what a baseline needs.
    static func counted(_ note: TodayPresentation.Note?) -> OrbitGaugeCalibration.Signal {
        if note == .needsVitals { return .heartRateNights }
        switch note?.countedSignal {
        case .hrv?: return .hrv
        case .restingHR?: return .restingHR
        case nil: return .anyNight
        }
    }

    /// The baselines count beside the mode (S1, S2), nil without one.
    var calibration: OrbitGaugeCalibration? {
        switch self {
        case .calibrating(let c): return c
        case .scored(_, let learning): return learning
        case .assembling, .pending: return nil
        }
    }
}

extension OrbitGaugeValues {
    /// The tiles' day as the orbit: Recovery as the tile shows it (withheld beside the baselines counter), sleep
    /// performance and strain of the same day, the gauge's readiness in the centre.
    init(_ tiles: TodayPresentation.Tiles, readiness: Int?) {
        self.init(readiness: readiness, recoveryScore: tiles.recovery, sleepPerformance: tiles.source?.sleepPerformance,
                  strain: tiles.source?.strain)
    }
}
