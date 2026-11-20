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
        case .pct1rm: return String(localized: "%\u{00A0}1RM")
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

    /// The record in the same words as its push (`PR_BODY_*` in Localizable.xcstrings):
    /// "Estimated one-rep max 102.5 kg.", "8 reps in one set, your most yet."
    func sentence(_ value: Double) -> String {
        let key: String
        let argument: String
        switch self {
        case .e1rm: key = "PR_BODY_E1RM"; argument = value.formatted(.number.precision(.fractionLength(0...1)))
        case .maxWeight: key = "PR_BODY_MAX_WEIGHT"; argument = value.formatted(.number.precision(.fractionLength(0...1)))
        case .maxReps: key = "PR_BODY_MAX_REPS"; argument = "\(Int(value.rounded()))"
        case .maxVolume: key = "PR_BODY_MAX_VOLUME"; argument = value.formatted(.number.precision(.fractionLength(0)))
        }
        return String(format: Bundle.main.localizedString(forKey: key, value: nil, table: nil), argument)
    }

    func format(_ value: Double) -> String {
        switch self {
        case .maxReps: return String(localized: "\(Int(value)) reps")
        case .maxVolume: return Fmt.volume(value)
        case .e1rm, .maxWeight: return Fmt.kg(value)
        }
    }
}

extension Muscle {
    var title: String {
        switch self {
        case .chest: return String(localized: "Chest")
        case .lats: return String(localized: "Lats")
        case .upperBack: return String(localized: "Upper back")
        case .traps: return String(localized: "Traps")
        case .frontDelts: return String(localized: "Front delts")
        case .sideDelts: return String(localized: "Side delts")
        case .rearDelts: return String(localized: "Rear delts")
        case .biceps: return String(localized: "Biceps")
        case .triceps: return String(localized: "Triceps")
        case .forearms: return String(localized: "Forearms")
        case .abs: return String(localized: "Abs")
        case .obliques: return String(localized: "Obliques")
        case .lowerBack: return String(localized: "Lower back")
        case .glutes: return String(localized: "Glutes")
        case .quads: return String(localized: "Quads")
        case .hamstrings: return String(localized: "Hamstrings")
        case .adductors: return String(localized: "Adductors")
        case .calves: return String(localized: "Calves")
        }
    }
}

// MARK: - buttons and rows

/// The big teal call to action, 56 pt tall. Area B's screens call `PillButton` (D6B-17); this stays for the callers outside
/// them until the gate (T5.9) deletes it.
struct TealButtonStyle: ButtonStyle {
    var prominent = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ryft(.headline))
            .foregroundStyle(prominent ? Theme.onAccent : Theme.accent)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(prominent ? Theme.accent : Theme.accent.opacity(0.14), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Theme.Motion.respecting(reduceMotion, PressableButtonStyle.pressAnimation), value: configuration.isPressed)
    }
}

/// The resume banner's numbers (PR 6 B §3.1, `b-23`).
enum WorkoutBannerSpec {
    /// 68 high at least (it grows with its text), radius 22, `surface`, a 1 pt ink 20 % border: the one outlined row, because
    /// it is the live thing.
    nonisolated static let minHeight: CGFloat = 68, radius: CGFloat = 22, borderOpacity = 0.20
    /// 16 at the sides, 12 above and below the text, 12 between the dot, the text and "Resume"; the meta 2 under the title.
    nonisolated static let sidePadding: CGFloat = 16, verticalPadding: CGFloat = 12, spacing: CGFloat = 12
    nonisolated static let metaGap: CGFloat = 2
    /// The 8 pt `textPrimary` dot pulses 1 → 0.35 over 1 s (static under Reduce Motion). Not Volt: Strain's screen has its
    /// needle.
    nonisolated static let dot: CGFloat = 8, pulseOpacity = 0.35, pulseDuration: Double = 1
    /// The minutes in the meta line move on every 30 s.
    nonisolated static let refreshInterval: TimeInterval = 30
}

/// "Workout in progress", "Upper A · 23 min · 6 sets done" and a light "Resume" (PR 6 B §3.1): resumes the live session, on
/// Strain's Train group and on Today. The whole banner is the one button (`train.resume`); VoiceOver reads "Workout in
/// progress", then "Upper A, 23 minutes, 6 sets done", with the hint "Opens the workout". The "Resume" pill is its look,
/// not a second button. From AX1 the pill goes under the text.
struct WorkoutInProgressBanner: View {
    let session: LocalSession
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        TimelineView(.periodic(from: .now, by: WorkoutBannerSpec.refreshInterval)) { context in
            let minutes = Self.minutes(since: session.startedAt, now: context.date)
            let sets = session.completedSetCount
            Button(action: action) {
                label(meta: Self.meta(title: session.title, minutes: minutes, sets: sets))
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(Text("Workout in progress", comment: "The resume banner's title: a workout is running."))
            .accessibilityValue(Text(verbatim: Self.spoken(title: session.title, minutes: minutes, sets: sets)))
            .accessibilityHint(Text("Opens the workout"))
            .accessibilityIdentifier("train.resume")
        }
    }

    private func label(meta: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: WorkoutBannerSpec.radius, style: .continuous)
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: WorkoutBannerSpec.spacing))
            : AnyLayout(HStackLayout(alignment: .center, spacing: WorkoutBannerSpec.spacing))
        // The dot beside both lines; once they wrap, beside the title.
        let dotAlignment: VerticalAlignment = typeSize.isAccessibilitySize ? .firstTextBaseline : .center
        return layout {
            HStack(alignment: dotAlignment, spacing: WorkoutBannerSpec.spacing) {
                PulsingDot()
                VStack(alignment: .leading, spacing: WorkoutBannerSpec.metaGap) {
                    Text("Workout in progress", comment: "The resume banner's title: a workout is running.")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: meta)
                        .font(.ryft(.caption))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The pill's look; the banner is the button. Its one line never wraps (`PillButton.compact`).
            PillButton(Text("Resume"), size: .compact) {}
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, WorkoutBannerSpec.sidePadding)
        .padding(.vertical, WorkoutBannerSpec.verticalPadding)
        .frame(maxWidth: .infinity, minHeight: WorkoutBannerSpec.minHeight, alignment: .leading)
        .background(Theme.surface, in: shape)
        .overlay {
            shape.strokeBorder(Theme.textPrimary.opacity(WorkoutBannerSpec.borderOpacity), lineWidth: Theme.Metrics.hairline)
        }
        .contentShape(shape)
    }

    /// Whole minutes since `start`, never negative (a clock moved back).
    nonisolated static func minutes(since start: Date, now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(start) / 60))
    }

    /// "Upper A · 23 min · 6 sets done".
    static func meta(title: String, minutes: Int, sets: Int) -> String {
        String(localized: "\(title) · \(minutes)\u{00A0}min · \(sets) sets done",
               comment: "The resume banner's meta line: the session's title, the minutes since it started, the sets checked off.")
    }

    /// "Upper A, 23 minutes, 6 sets done": the meta line for VoiceOver.
    static func spoken(title: String, minutes: Int, sets: Int) -> String {
        String(localized: "\(title), \(Fmt.spokenDuration(minutes: minutes)), \(sets) sets done",
               comment: "VoiceOver value of the resume banner: the session's title, how long it has run (\"23 minutes\"), the sets checked off.")
    }
}

/// The banner's 8 pt dot: `textPrimary`, its opacity going 1 → 0.35 and back every second; still under Reduce Motion.
private struct PulsingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(Theme.textPrimary)
            .frame(width: WorkoutBannerSpec.dot, height: WorkoutBannerSpec.dot)
            .opacity(reduceMotion || !dimmed ? 1 : WorkoutBannerSpec.pulseOpacity)
            .onAppear { pulse() }
            .onChange(of: reduceMotion) { pulse() }
            .accessibilityHidden(true)
    }

    private func pulse() {
        dimmed = false
        guard !reduceMotion else { return }
        let pulse = Animation.easeInOut(duration: WorkoutBannerSpec.pulseDuration).repeatForever(autoreverses: true)
        withAnimation(Theme.Motion.respecting(reduceMotion, pulse)) { dimmed = true }
    }
}

/// The record row's numbers (PR 6 B §5.1 row 4, §7.3).
enum PRBadgeSpec {
    /// 52 high at least, 12 between the trophy disc, the text and the value; the detail 2 under the title.
    nonisolated static let minHeight: CGFloat = 52, spacing: CGFloat = 12, detailGap: CGFloat = 2
    /// The value: 20 Light at the default size, growing like `.title3`; from AX1 it goes under the text, this far.
    nonisolated static let valueSize: CGFloat = 20, stackedValueGap: CGFloat = 4
}

/// A personal record (D6B-9): the trophy in a 36 pt outline disc (ink, no amber), the exercise (`callout`) over the kind
/// (`caption`, `textSecondary`: "Est. 1RM", "Most reps"), or the kind over its date ("Nov 13") on the exercise's own page, and
/// the value at the right in 20 Light ("93.5 kg"). The record's sentence ("Estimated one-rep max 93.5 kg.") is VoiceOver's:
/// one element, the exercise with the sentence as its value, or the sentence with the date.
struct PRBadge: View {
    let record: PersonalRecord
    var exerciseName: String?
    var showsDate = false

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title3) private var valueSize: CGFloat = PRBadgeSpec.valueSize

    var body: some View {
        HStack(alignment: .center, spacing: PRBadgeSpec.spacing) {
            IconDisc(systemImage: "trophy")
            VStack(alignment: .leading, spacing: PRBadgeSpec.detailGap) {
                Text(verbatim: Self.title(record, exerciseName: exerciseName))
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = Self.detail(record, exerciseName: exerciseName, showsDate: showsDate) {
                    Text(verbatim: detail)
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if typeSize.isAccessibilitySize {
                    value.padding(.top, PRBadgeSpec.stackedValueGap - PRBadgeSpec.detailGap)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !typeSize.isAccessibilitySize {
                value
            }
        }
        .frame(maxWidth: .infinity, minHeight: PRBadgeSpec.minHeight, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: Self.spokenLabel(record, exerciseName: exerciseName)))
        .accessibilityValue(Text(verbatim: Self.spokenValue(record, exerciseName: exerciseName, showsDate: showsDate)))
    }

    private var value: some View {
        Text(verbatim: record.kind.format(record.value))
            .font(.ryftNumber(size: valueSize, weight: .light))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .fixedSize()
    }

    /// The exercise, or the kind on the exercise's own page.
    static func title(_ record: PersonalRecord, exerciseName: String?) -> String {
        exerciseName ?? record.kind.title
    }

    /// Under the title: the kind (under the exercise), or the date (under the kind).
    static func detail(_ record: PersonalRecord, exerciseName: String?, showsDate: Bool, now: Date = .now) -> String? {
        if exerciseName != nil { return record.kind.title }
        return showsDate ? date(record.achievedAt, now: now) : nil
    }

    /// "Nov 13"; "Nov 13, 2025" for a record from another year.
    static func date(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        calendar.isDate(date, equalTo: now, toGranularity: .year)
            ? date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// VoiceOver's label: the exercise, or (on its own page) the record's sentence.
    static func spokenLabel(_ record: PersonalRecord, exerciseName: String?) -> String {
        exerciseName ?? record.kind.sentence(record.value)
    }

    /// VoiceOver's value: the sentence after the exercise, or the date after the sentence.
    static func spokenValue(_ record: PersonalRecord, exerciseName: String?, showsDate: Bool) -> String {
        if exerciseName != nil { return record.kind.sentence(record.value) }
        return showsDate ? record.achievedAt.formatted(.dateTime.month(.wide).day().year()) : ""
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

#Preview("Train components") {
    TrainComponentsPreview()
        .previewEnvironment()
}

#Preview("Train components · AX3") {
    TrainComponentsPreview()
        .previewEnvironment()
        .environment(\.dynamicTypeSize, .accessibility3)
}

/// The banner (six sets in), the records as the summary and the exercise page list them, and the will-sync note.
private struct TrainComponentsPreview: View {
    var body: some View {
        ScrollView {
            DarkPreview {
                VStack(alignment: .leading, spacing: 16) {
                    WorkoutInProgressBanner(session: MockTrain.liveSession(in: TrainPreview.store, checked: 6)) {}
                    Card {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(MockTrain.completed.prs, id: \.self) { pr in
                                PRBadge(record: pr, exerciseName: pr.exerciseId == MockTrain.bench.id ? "Bench press" : "Barbell row")
                            }
                        }
                    }
                    Card { PRBadge(record: MockTrain.completed.prs[0], showsDate: true) }
                    WillSyncNote()
                }
            }
        }
        .background(Theme.background)
    }
}
