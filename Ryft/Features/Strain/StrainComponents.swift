import SwiftUI

/// Icon and display name per `Workout.activity` (names from HealthKitManager.activityName).
enum ActivityStyle {
    static func icon(for activity: String) -> String {
        switch activity {
        case "running": return "figure.run"
        case "walking": return "figure.walk"
        case "hiking": return "figure.hiking"
        case "cycling": return "figure.outdoor.cycle"
        case "swimming": return "figure.pool.swim"
        case "rowing": return "figure.rower"
        case "elliptical": return "figure.elliptical"
        case "stairs": return "figure.stair.stepper"
        case "strength", "functional_strength": return "dumbbell.fill"
        case "crossfit", "hiit": return "figure.highintensity.intervaltraining"
        case "yoga": return "figure.yoga"
        case "core": return "figure.core.training"
        case "soccer": return "figure.soccer"
        case "tennis": return "figure.tennis"
        case "xc_skiing": return "figure.skiing.crosscountry"
        case "skiing": return "figure.skiing.downhill"
        case "snowboarding": return "figure.snowboarding"
        case "cooldown": return "figure.cooldown"
        default: return "figure.mixed.cardio"
        }
    }

    static func name(for activity: String) -> String {
        switch activity {
        case "running": return String(localized: "Run")
        case "walking": return String(localized: "Walk")
        case "hiking": return String(localized: "Hike")
        case "cycling": return String(localized: "Ride")
        case "swimming": return String(localized: "Swim")
        case "strength": return String(localized: "Strength")
        case "functional_strength": return String(localized: "Functional strength")
        case "hiit": return String(localized: "HIIT")
        case "xc_skiing": return String(localized: "Cross-country ski")
        case "other": return String(localized: "Workout")
        default: return activity.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

/// A row in Strain's activity list.
enum ActivityItem: Identifiable {
    /// A workout, with its logged Train session when `session_id` matches.
    case workout(Workout, SessionSummary?)
    /// A logged session no workout points at (yet).
    case session(SessionSummary)

    var id: UUID {
        switch self {
        case .workout(let w, _): return w.id
        case .session(let s): return s.id
        }
    }

    var start: Date {
        switch self {
        case .workout(let w, _): return w.start
        case .session(let s): return s.startedAt
        }
    }
}

/// Activity list row: icon, name, duration · avg HR, strain pill. A workout
/// with a logged session shows the dumbbell, the session's title and its load.
struct ActivityRow: View {
    let workout: Workout
    var session: SessionSummary? = nil

    private var title: String {
        if let session, !session.title.isEmpty { return session.title }
        return ActivityStyle.name(for: workout.activity)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: session == nil ? ActivityStyle.icon(for: workout.activity) : "dumbbell.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .background(Theme.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.ryft(.caption))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if session != nil || workout.muscularLoad != nil {
                LoadChip(load: session?.muscularTrimp ?? workout.muscularLoad)
            }
            StrainPill(strain: workout.strain)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [Fmt.time(workout.start), Fmt.duration(seconds: workout.duration)]
        if let hr = workout.avgHr { parts.append(String(localized: "\(Int(hr.rounded())) bpm")) }
        return parts.joined(separator: " · ")
    }
}

/// A logged session in Strain's list: dumbbell, title, time · duration · volume, load.
struct SessionActivityRow: View {
    let session: SessionSummary

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .background(Theme.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title.isEmpty ? String(localized: "Workout") : session.title)
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.ryft(.caption))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            LoadChip(load: session.muscularTrimp)
            StrainPill(strain: session.strain)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [Fmt.time(session.startedAt)]
        if let min = session.durationMin { parts.append(Fmt.duration(minutes: min)) }
        if let v = session.volumeKg { parts.append(Fmt.volume(v)) }
        return parts.joined(separator: " · ")
    }
}

struct StrainPill: View {
    let strain: Double?

    var body: some View {
        Text(Fmt.strain(strain))
            .font(.ryft(.callout))
            .monospacedDigit()
            .foregroundStyle(strain == nil ? Theme.textTertiary : Theme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background((strain == nil ? Theme.surfaceRaised : Theme.accent.opacity(0.14)), in: Capsule())
            .accessibilityLabel(Text("Strain \(Fmt.strain(strain))"))
    }
}

#Preview("Strain components", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 14) {
            ForEach(MockData.todayDetail.workouts) { ActivityRow(workout: $0) }
            if let s = MockTrain.history.last.map(SessionSummary.init),
               let w = MockData.allWorkouts.first(where: { $0.sessionId == s.id }) {
                ActivityRow(workout: w, session: s)
                SessionActivityRow(session: s)
            }
        }
    }
}
