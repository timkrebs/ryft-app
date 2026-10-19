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

/// Five HRR zones as a stacked bar plus a legend with minutes.
struct ZoneMinutesView: View {
    /// Minutes in zones 1–5; nil or empty renders a placeholder.
    let minutes: [Double]?

    private static let labels = ["50–60%", "60–70%", "70–80%", "80–90%", "90%+"]

    private var values: [Double] {
        guard let minutes, minutes.count == 5 else { return [] }
        return minutes
    }

    var body: some View {
        let total = values.reduce(0, +)
        VStack(alignment: .leading, spacing: 14) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    if total <= 0 {
                        Rectangle().fill(Theme.surfaceRaised)
                    } else {
                        ForEach(values.indices, id: \.self) { i in
                            if values[i] > 0 {
                                Rectangle()
                                    .fill(Theme.zones[i])
                                    .frame(width: max(2, (geo.size.width - 8) * values[i] / total))
                            }
                        }
                    }
                }
            }
            .frame(height: 14)
            .clipShape(Capsule())

            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { i in
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Circle().fill(Theme.zones[i]).frame(width: 7, height: 7)
                            Text("Z\(i + 1)")
                                .font(.ryft(.caption))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Text(values.isEmpty ? Fmt.placeholder : Fmt.duration(minutes: Int(values[i].rounded())))
                            .font(.ryft(.callout))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                        Text(Self.labels[i])
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Heart-rate zones"))
        .accessibilityValue(Text(values.isEmpty ? String(localized: "No data")
            : values.enumerated().map { "Zone \($0.offset + 1): \(Int($0.element.rounded())) min" }.joined(separator: ", ")))
    }
}

/// Activity list row: icon, name, duration · avg HR, strain pill.
struct ActivityRow: View {
    let workout: Workout

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: ActivityStyle.icon(for: workout.activity))
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .background(Theme.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(ActivityStyle.name(for: workout.activity))
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
            ZoneMinutesView(minutes: MockData.todayDetail.strain?.zoneMin.map(Double.init))
            ZoneMinutesView(minutes: nil)
            ForEach(MockData.todayDetail.workouts) { ActivityRow(workout: $0) }
        }
    }
}
