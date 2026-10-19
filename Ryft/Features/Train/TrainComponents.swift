import SwiftUI

// MARK: - display names

extension ExerciseKind {
    var title: String {
        switch self {
        case .barbell: return String(localized: "Barbell")
        case .dumbbell: return String(localized: "Dumbbell")
        case .kettlebell: return String(localized: "Kettlebell")
        case .bodyweight: return String(localized: "Bodyweight")
        case .machine: return String(localized: "Machine")
        case .cable: return String(localized: "Cable")
        case .cardio: return String(localized: "Cardio")
        }
    }
}

extension LoadType {
    var title: String {
        switch self {
        case .weight: return String(localized: "Weight")
        case .bodyweight: return String(localized: "Bodyweight")
        case .time: return String(localized: "Time")
        case .distance: return String(localized: "Distance")
        }
    }
}

extension PlanGoal {
    var title: String {
        switch self {
        case .strength: return String(localized: "Strength")
        case .hypertrophy: return String(localized: "Hypertrophy")
        case .weightlifting: return String(localized: "Weightlifting")
        case .general: return String(localized: "General")
        }
    }
}

extension TargetKind {
    var title: String {
        switch self {
        case .pct1rm: return String(localized: "% 1RM")
        case .rpe: return String(localized: "RPE")
        case .kg: return String(localized: "kg")
        case .bodyweight: return String(localized: "Bodyweight")
        }
    }
}

extension ProgressionType {
    var title: String {
        switch self {
        case .linear: return String(localized: "Linear +2.5 kg")
        case .percent: return String(localized: "Percent-based")
        case .none: return String(localized: "None")
        }
    }
}

extension PRKind {
    var title: String {
        switch self {
        case .e1rm: return String(localized: "Est. 1RM")
        case .maxWeight: return String(localized: "Heaviest")
        case .maxReps: return String(localized: "Most reps")
        case .maxVolume: return String(localized: "Most volume")
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .maxReps: return String(localized: "\(Int(value)) reps")
        case .maxVolume: return Fmt.volume(value)
        case .e1rm, .maxWeight: return Fmt.kg(value)
        }
    }
}

enum Muscle {
    /// Display name for an API muscle id ("quads").
    static func title(_ id: String) -> String {
        switch id {
        case "chest": return String(localized: "Chest")
        case "back": return String(localized: "Back")
        case "shoulders": return String(localized: "Shoulders")
        case "quads": return String(localized: "Quads")
        case "hamstrings": return String(localized: "Hamstrings")
        case "glutes": return String(localized: "Glutes")
        case "biceps": return String(localized: "Biceps")
        case "triceps": return String(localized: "Triceps")
        case "core": return String(localized: "Core")
        case "calves": return String(localized: "Calves")
        case "traps": return String(localized: "Traps")
        case "forearms": return String(localized: "Forearms")
        default: return id.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

// MARK: - buttons and rows

/// The big teal call to action ("Start workout"), 56 pt tall.
struct TealButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ryft(.headline))
            .foregroundStyle(prominent ? Theme.graphite : Theme.accent)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(prominent ? Theme.accent : Theme.accent.opacity(0.14), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// "My plans ›" rows: icon, title, optional detail.
struct TrainLinkRow: View {
    let title: String
    var detail: String? = nil
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 40, height: 40)
                .background(Theme.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.textPrimary)
                if let detail {
                    Text(detail)
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(14)
        .frame(minHeight: 56)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// "Workout in progress · 23 min" — resumes the live session.
struct WorkoutInProgressBanner: View {
    let session: LocalSession
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let minutes = max(0, Int(context.date.timeIntervalSince(session.startedAt) / 60))
                HStack(spacing: 14) {
                    PulsingDot()
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Workout in progress · \(minutes) min")
                            .font(.ryft(.body))
                            .foregroundStyle(Theme.textPrimary)
                        Text("\(session.title) · \(session.completedSetCount) sets done")
                            .font(.ryft(.caption))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Text("Resume")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.graphite)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 40)
                        .background(Theme.accent, in: Capsule())
                }
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.5), lineWidth: Theme.Metrics.hairline))
            }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityHint(Text("Opens the workout"))
        .accessibilityIdentifier("train.resume")
    }
}

private struct PulsingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false

    var body: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: 10, height: 10)
            .opacity(on ? 0.35 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1).repeatForever()) { on = true }
            }
            .accessibilityHidden(true)
    }
}

/// Muscular load chip next to a session ("Load 84.6").
struct LoadChip: View {
    let load: Double?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "dumbbell.fill").imageScale(.small)
            Text(Fmt.load(load))
                .monospacedDigit()
        }
        .font(.ryft(.caption))
        .foregroundStyle(load == nil ? Theme.textTertiary : Theme.accentSecondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Theme.accentSecondary.opacity(load == nil ? 0.06 : 0.14), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Muscular load \(Fmt.load(load))"))
    }
}

/// A personal record: trophy, kind, value.
struct PRBadge: View {
    let record: PersonalRecord
    var exerciseName: String? = nil
    var showsDate = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.warning)
                .frame(width: 34, height: 34)
                .background(Theme.warning.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                if let exerciseName {
                    Text(exerciseName)
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textPrimary)
                }
                Text(showsDate ? "\(record.kind.title) · \(record.achievedAt.formatted(.dateTime.day().month(.abbreviated).year()))"
                               : record.kind.title)
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 6)
            Text(record.kind.format(record.value))
                .font(.ryft(.body))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Will sync" note while a finished session waits for the network.
struct WillSyncNote: View {
    var body: some View {
        Label("Saved on this phone. Will sync when you're back online.", systemImage: "icloud.and.arrow.up")
            .font(.ryft(.caption))
            .foregroundStyle(Theme.textSecondary)
    }
}

/// Section title used on Train screens ("TRAIN").
struct TrainSectionTitle: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .ryftLabelStyle()
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview("Train components", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 14) {
            Button("Start workout") {}.buttonStyle(TealButtonStyle())
            WorkoutInProgressBanner(session: MockTrain.liveSession(in: TrainPreview.store)) {}
            TrainLinkRow(title: "My plans", detail: "Upper/Lower 4× · week 6", systemImage: "list.bullet.rectangle")
            HStack { LoadChip(load: 84.6); LoadChip(load: nil); StrainPill(strain: 9.8) }
            PRBadge(record: MockTrain.completed.prs[0], exerciseName: "Bench press")
            WillSyncNote()
        }
    }
}
