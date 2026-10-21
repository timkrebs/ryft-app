import SwiftUI
import UIKit

/// Sleep → Planner: pick a wake time, get three bedtimes (100 / 85 / 70 % of
/// tonight's need), the time in bed behind them, and why the need is what it is.
struct SleepPlannerSection: View {
    let model: SleepPlannerViewModel
    @State private var showsWhy = false

    @Environment(ScreenModels.self) private var screens

    var body: some View {
        VStack(spacing: Theme.Metrics.sectionSpacing) {
            // Tonight, from your schedule; below, any other wake time to try.
            TonightCard(planner: screens.bedtime)
            Text("Try another wake time")
                .ryftLabelStyle()
                .frame(maxWidth: .infinity, alignment: .leading)
            Card {
                DatePicker("Wake up at", selection: Binding(get: { model.wake }, set: { model.setWake($0) }),
                           displayedComponents: .hourAndMinute)
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.accent)
            }
            if let plan = model.plan {
                bedtimes(plan)
                why(plan)
                if let asOf = model.asOf {
                    Label(String(localized: "As of \(asOf.formatted(date: .abbreviated, time: .shortened))"),
                          systemImage: "clock.arrow.circlepath")
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                }
            } else if model.isLoading {
                ProgressView().tint(Theme.accent).padding(.top, 40)
            } else if let error = model.error {
                InlineMessage(message: error, retry: { await model.load() })
            }
        }
    }

    private func bedtimes(_ plan: SleepPlan) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(title: "Go to bed")
                ForEach(model.options) { option in
                    HStack(alignment: .firstTextBaseline) {
                        Text(Fmt.time(option.bedtime))
                            .font(.ryft(.metric))
                            .monospacedDigit()
                            .foregroundStyle(option.share == 100 ? Theme.textPrimary : Theme.textSecondary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(option.share) % of your need")
                                .font(.ryft(.callout))
                                .foregroundStyle(Theme.textPrimary)
                            Text("\(Fmt.duration(minutes: option.sleepMin)) asleep")
                                .font(.ryft(.caption))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    if option.share != 70 { Divider().overlay(Theme.separator) }
                }
                Text("Time in bed \(Fmt.duration(minutes: plan.inBedMin)) at \(plan.efficiency) % efficiency.")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func why(_ plan: SleepPlan) -> some View {
        Card {
            DisclosureGroup(isExpanded: $showsWhy) {
                NeedBasisRows(plan: plan).padding(.top, 10)
            } label: {
                Text("Why this need")
                    .font(.ryft(.headline))
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.textSecondary)
        }
    }
}

/// Tonight's need, term by term (`GET /v1/sleep/plan` → `basis`).
struct NeedBasisRows: View {
    let plan: SleepPlan

    var body: some View {
        VStack(spacing: 10) {
            StatRow(title: "Baseline", value: Fmt.duration(minutes: plan.basis.base))
            StatRow(title: "Today's strain so far", value: "+" + Fmt.duration(minutes: plan.basis.strainTopup))
            StatRow(title: "Sleep debt", value: "+" + Fmt.duration(minutes: plan.basis.debtTopup))
            if plan.basis.napCredit > 0 {
                StatRow(title: "Nap credit", value: Fmt.duration(minutes: -plan.basis.napCredit))
            }
            Divider().overlay(Theme.separator)
            StatRow(title: "Tonight's need", value: Fmt.duration(minutes: plan.needMin))
        }
    }
}

// MARK: - Bedtime & wake

/// Tonight: when to be in bed for the goal, the wake time and the need, the other two goals,
/// and why the need is what it is. Numbers only from `GET /v1/sleep/plan`. Without a schedule:
/// an invitation to set one.
struct TonightCard: View {
    let planner: BedtimePlanner
    @State private var showsWhy = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Tonight")
                if let schedule = planner.schedule, let plan = planner.plan, let bed = planner.bedtime {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("In bed by")
                                .font(.ryft(.body))
                                .foregroundStyle(Theme.textSecondary)
                            Text(Fmt.time(bed))
                                .font(.ryft(.metric))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textPrimary)
                            Text("for \(schedule.goal.rawValue) %")
                                .font(.ryft(.body))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Text("Wake \(Fmt.time(plan.wake)) · need \(Fmt.duration(minutes: plan.needMin))")
                            .font(.ryft(.callout))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    VStack(spacing: 8) {
                        ForEach(SleepSchedule.Goal.allCases) { goal in
                            HStack {
                                Text("\(goal.title) · \(goal.rawValue) %")
                                    .foregroundStyle(goal == schedule.goal ? Theme.textPrimary : Theme.textSecondary)
                                Spacer()
                                Text(Fmt.time(goal.bedtime(in: plan)))
                                    .monospacedDigit()
                                    .foregroundStyle(goal == schedule.goal ? Theme.textPrimary : Theme.textSecondary)
                            }
                            .font(.ryft(.callout))
                            .accessibilityElement(children: .combine)
                        }
                    }
                    DisclosureGroup(isExpanded: $showsWhy) {
                        NeedBasisRows(plan: plan).padding(.top, 8)
                    } label: {
                        Text("Why this need")
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .tint(Theme.textSecondary)
                    scheduleLink(title: "Bedtime & wake")
                } else if planner.schedule == nil {
                    Text("Tell RYFT when you want to wake up. It tells you when to go to bed, with what today's strain and your sleep debt add.")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    scheduleLink(title: "Set up Bedtime & wake")
                } else if let error = planner.error {
                    InlineMessage(message: error, retry: { await planner.refresh() })
                } else {
                    ProgressView().tint(Theme.accent)
                }
            }
        }
        .task { if planner.plan == nil { await planner.refresh() } }
        .accessibilityIdentifier("tonight.card")
    }

    private func scheduleLink(title: LocalizedStringKey) -> some View {
        NavigationLink {
            SleepScheduleView(planner: planner)
        } label: {
            Label(title, systemImage: "bed.double")
                .font(.ryft(.callout))
                .foregroundStyle(Theme.accent)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }
}

/// Bedtime & wake: wake times (weekdays and weekend, or each day), the goal, the wind-down,
/// the reminder and the alarm. Each change saves and plans again.
struct SleepScheduleView: View {
    let planner: BedtimePlanner
    @State private var draft: SleepSchedule
    @State private var reminderRefused = false
    @State private var alarmRefused = false
    @State private var saving: Task<Void, Never>?
    @Environment(\.openURL) private var openURL

    init(planner: BedtimePlanner) {
        self.planner = planner
        _draft = State(initialValue: planner.draft)
    }

    private static let weekdayNames: [String] = {
        // Monday first, in the user's language.
        let symbols = Calendar.current.standaloneWeekdaySymbols
        return Array(symbols[1...]) + [symbols[0]]
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Metrics.sectionSpacing) {
                wake
                goal
                windDown
                reminder
                alarm
            }
            .padding(Theme.Metrics.screenPadding)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(Text("Bedtime & wake"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        // Saves a moment after the last change (a wheel sends many).
        .onChange(of: draft) { _, new in
            saving?.cancel()
            saving = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await planner.update(new)
            }
        }
        .onDisappear {
            // A change made just before leaving still counts.
            if draft != planner.schedule { Task { await planner.update(draft) } }
        }
    }

    private var wake: some View {
        section("Wake up at") {
            Toggle("Same time on weekdays", isOn: $draft.sameOnWeekdays)
                .font(.ryft(.body))
                .tint(Theme.accent)
            if draft.sameOnWeekdays {
                timePicker("Weekdays", index: 0) { draft.setWeekdays($0) }
                timePicker("Weekend", index: 5) { draft.setWeekend($0) }
            } else {
                ForEach(0..<7, id: \.self) { i in
                    timePicker(LocalizedStringKey(Self.weekdayNames[i]), index: i) { draft.wake[i] = $0 }
                }
            }
        }
    }

    private var goal: some View {
        section("Aim for") {
            ForEach(SleepSchedule.Goal.allCases) { goal in
                Button {
                    draft.goal = goal
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(goal.title).font(.ryft(.body)).foregroundStyle(Theme.textPrimary)
                            Text("\(goal.rawValue) % of your need").font(.ryft(.caption)).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        if draft.goal == goal {
                            Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                        }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(draft.goal == goal ? .isSelected : [])
            }
        }
    }

    private var windDown: some View {
        section("Wind down") {
            Picker("Remind me before bedtime", selection: $draft.windDownMin) {
                ForEach(SleepSchedule.windDownChoices, id: \.self) { Text("\($0) min").tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var reminder: some View {
        section("Bedtime reminder") {
            Toggle(isOn: Binding(get: { draft.reminderOn }, set: { on in
                guard on else { draft.reminderOn = false; return }
                Task {
                    if await planner.allowReminders() { draft.reminderOn = true } else { reminderRefused = true }
                }
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remind me to wind down").font(.ryft(.body)).foregroundStyle(Theme.textPrimary)
                    Text("A notification \(draft.windDownMin) min before tonight's bedtime. It moves with your day.")
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.accent)
            .accessibilityIdentifier("schedule.reminder")
            if reminderRefused { refused }
        }
    }

    private var alarm: some View {
        section("Wake-up alarm") {
            Toggle(isOn: Binding(get: { draft.alarmOn }, set: { on in
                guard on else { draft.alarmOn = false; return }
                Task {
                    if await planner.allowAlarm() { draft.alarmOn = true } else { alarmRefused = true }
                }
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wake me at my wake time").font(.ryft(.body)).foregroundStyle(Theme.textPrimary)
                    Text(planner.alarmsRing
                         ? "A real alarm: it rings in Silent mode and Focus, with Stop and Snooze."
                         : "A notification at your wake time. It won't ring like an alarm on this iOS version.")
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.accent)
            if alarmRefused { refused }
        }
    }

    /// iOS said no: where to change it.
    private var refused: some View {
        HStack {
            Text("Not allowed in iOS Settings.")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.warning)
            Spacer()
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .font(.ryft(.caption))
            .foregroundStyle(Theme.accent)
        }
    }

    private func timePicker(_ title: LocalizedStringKey, index: Int, set: @escaping (String) -> Void) -> some View {
        DatePicker(title, selection: Binding(
            get: { SleepSchedule.date(draft.wake[index], on: .now) },
            set: { set(SleepPlannerViewModel.hhmm($0)) }), displayedComponents: .hourAndMinute)
            .font(.ryft(.body))
            .tint(Theme.accent)
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        let body = content()
        return VStack(alignment: .leading, spacing: 10) {
            Text(title).ryftLabelStyle()
            Card { VStack(alignment: .leading, spacing: 12) { body } }
        }
    }
}

#Preview("Planner · dark") {
    let state = AppState.preview(flags: [.sleepPlanner: true])
    let model = SleepPlannerViewModel(state: state)
    return ScrollView { SleepPlannerSection(model: model).padding() }
        .background(Theme.background)
        .task { await model.load() }
        .previewEnvironment(state)
}

#Preview("Planner · light") {
    let state = AppState.preview(flags: [.sleepPlanner: true])
    let model = SleepPlannerViewModel(state: state)
    return ScrollView { SleepPlannerSection(model: model).padding() }
        .background(Theme.background)
        .task { await model.load() }
        .previewEnvironment(state, scheme: .light)
}
