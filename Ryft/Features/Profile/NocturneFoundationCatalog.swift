#if DEBUG
import SwiftUI

/// The catalog's "Nocturne · foundation" section (docs/work/2026-11-16-nocturne/build-plan.md §2, T6.0): the subpage header
/// and its pinned bar, the sheet header, form fields and value chips, the steppers, the legend mark, the banner, and the
/// restyled setup parts (check rows, capability rows, numbered steps, the step rule, selectable tiles, the tracker card).
/// Its own file, so the other tickets' sections merge beside it. Verbatim words: the screens own the strings.
struct NocturneFoundationCatalog: View {
    /// The catalog's parts, in order; the shots (`NocturneFoundationShotsTests`) draw each on its own.
    enum Part: String, CaseIterable {
        case subpage, sheetHeader = "sheet-header", form, stepper, legend, banner
        case setupRows = "setup-rows", tiles, trackerCard = "tracker-card"
    }

    var parts: [Part] = Part.allCases

    @State private var email = "alex@example.com"
    @State private var password = ""
    @State private var name = ""
    @State private var start = Date(timeIntervalSince1970: 1_795_500_720)
    @State private var days = 4
    @State private var sets = 1
    @State private var minutes = 465
    @State private var picked: Set<String> = ["Garmin"]
    @FocusState private var focus: Field?

    private enum Field { case email, password, name }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(parts, id: \.self) { part($0) }
        }
        .environment(\.locale, Locale(identifier: "en_US"))
    }

    @ViewBuilder private func part(_ part: Part) -> some View {
        switch part {
        case .subpage: subpage
        case .sheetHeader: sheetHeaders
        case .form: form
        case .stepper: steppers
        case .legend: legend
        case .banner: banners
        case .setupRows: setupRows
        case .tiles: tiles
        case .trackerCard: trackerCard
        }
    }

    private var subpage: some View {
        VStack(alignment: .leading, spacing: 18) {
            caption("headers · pushed · pushed with a trailing circle · a sheet's root · back and close · a long title")
            PushedHeader(Text(verbatim: "Display"))
            PushedHeader(Text(verbatim: "Journal")) {
                CircleButton(systemImage: "plus", accessibilityLabel: Text(verbatim: "Add a habit")) {}
            }
            SheetHeader(Text(verbatim: "What do you wear?"))
            PushedHeader(Text(verbatim: "Match exercises")) {
                CircleButton(systemImage: "xmark", accessibilityLabel: Text(verbatim: "Close")) {}
            }
            PushedHeader(Text(verbatim: "Baseline sleep need for the week ahead"))
            caption("pinned bar · a disabled primary with its reason · a footnote and a quiet action")
            PinnedActionBar(caption: Text(verbatim: "Write a message first.")) {
                PillButton(Text(verbatim: "Send"), systemImage: PillButton.Icon.send) {}
                    .disabled(true)
            }
            .padding(.horizontal, -Theme.Metrics.screenPadding)
            PinnedActionBar(footnote: Text(verbatim: "You can change this later in Profile.")) {
                PillButton(Text(verbatim: "Done"), systemImage: PillButton.Icon.confirm) {}
                Button {} label: { Text(verbatim: "Show me again later") }
                    .ryftLink()
            }
            .padding(.horizontal, -Theme.Metrics.screenPadding)
        }
    }

    private var sheetHeaders: some View {
        VStack(alignment: .leading, spacing: 18) {
            caption("sheet header · close only · Cancel and a capped Save · Save disabled · a menu · saving (uncapped)")
            SheetHeader(Text(verbatim: "Start workout"))
            SheetHeader(Text(verbatim: "Add activity"), closeLabel: Text(verbatim: "Cancel")) {
                PillButton(Text(verbatim: "Save"), size: .compact) {}
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .accessibilityShowsLargeContentViewer()
            }
            SheetHeader(Text(verbatim: "Edit plan")) {
                PillButton(Text(verbatim: "Save"), size: .compact) {}.disabled(true)
            }
            SheetHeader(Text(verbatim: "Rest")) {
                CircleButton(systemImage: "ellipsis", accessibilityLabel: Text(verbatim: "More")) {}.headerEdgeButton()
            }
            SheetHeader(Text(verbatim: "Add sleep")) {
                PillButton(Text(verbatim: "Save"), size: .compact, busy: true) {}
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            caption("form field · focused · secure with the eye · a large value · chips")
            GroupedCard {
                FormField(Text(verbatim: "Email"), isFocused: focus == .email) {
                    TextField(text: $email, prompt: Text(verbatim: "name@example.com").fieldPrompt()) { Text(verbatim: "Email") }
                        .focused($focus, equals: .email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }
                FormField(Text(verbatim: "Password"), isFocused: focus == .password) {
                    SecureField(text: $password, prompt: Text(verbatim: "At least 8 characters").fieldPrompt()) {
                        Text(verbatim: "Password")
                    }
                    .focused($focus, equals: .password)
                } trailing: {
                    Image(systemName: "eye")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: Theme.Metrics.minHitTarget, height: Theme.Metrics.minHitTarget)
                        .accessibilityHidden(true)
                }
            }
            GroupedCard {
                FormField(Text(verbatim: "Name"), isFocused: true, valueSize: .large) {
                    TextField(text: $name, prompt: Text(verbatim: "Upper/Lower 4×").fieldPrompt()) { Text(verbatim: "Name") }
                        .focused($focus, equals: .name)
                }
            }
            GroupedCard {
                ValueChipRow(Text(verbatim: "Start")) {
                    ValueChip(Text(verbatim: "Start date"), date: $start, displayedComponents: .date)
                    ValueChip(Text(verbatim: "Start time"), date: $start, displayedComponents: .hourAndMinute)
                }
                GroupedRow.custom(Text(verbatim: "Rest")) { ValueChip(Text(verbatim: "3:00")) }
            }
        }
    }

    private var steppers: some View {
        VStack(alignment: .leading, spacing: 18) {
            caption("stepper rows · at the minimum · a quiet sub-row")
            GroupedCard {
                RyftStepperRow(Text(verbatim: "Days per week"), value: $days, in: 1...7)
                RyftStepperRow(Text(verbatim: "Sets"), quiet: true, value: $sets, in: 1...10)
            }
            caption("hero stepper · a dot numeral between the circles, its ruler hidden from VoiceOver")
            HeroStepper(Text(verbatim: "Baseline sleep need"),
                        value: RyftStepperValue($minutes, in: 240...720, step: 15, format: Self.clock)) {
                DotNumeral(Self.clock(minutes), glyphGap: DotNumeral.glyphGapDetail, placeholder: "0:00",
                           accessibilityLabel: Text(verbatim: "Baseline sleep need"))
            }
            RulerScale(range: 240...720, value: Double(minutes), tickCount: 33, labels: ["4 h", "8 h", "12 h"],
                       accessibilityLabel: Text(verbatim: "Baseline sleep need"), accessibilityValue: Text(verbatim: ""))
                .accessibilityHidden(true)
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 18) {
            caption("legend mark · recovery, strain, sleep")
            ForEach(Self.legendRows, id: \.0) { title, tint in
                HStack(spacing: 14) {
                    LegendMark(tint)
                    Text(verbatim: title).font(.ryft(.headline)).foregroundStyle(Theme.textPrimary)
                }
            }
        }
    }

    private var banners: some View {
        VStack(alignment: .leading, spacing: 12) {
            caption("banner · error with actions · retrying · notice · attention · destructive")
            InlineMessage(message: "Couldn't reach RYFT. Showing what was loaded earlier.",
                          details: "HTTP 503 · Request ID 01JD8K2V9Q7M3X", retry: {}, caption: "Showing data from 9:20",
                          identifier: "catalog.banner", announces: false)
            InlineMessage(message: "Couldn't reach RYFT. Showing what was loaded earlier.", retry: {}, isRetrying: true,
                          onDetails: {}, announces: false)
            InlineMessage(message: "Your file is ready. Sign in to continue.", systemImage: "doc.text", announces: false)
            InlineMessage(message: "Notifications are off for RYFT. Turn them on in Settings.", systemImage: "bell.slash",
                          action: ("Open Settings", {}), severity: .attention, announces: false)
            InlineMessage(message: "Your account is being deleted. This activity is deleted with it.", systemImage: "trash",
                          severity: .destructive, announces: false, readsAsOne: true)
        }
    }

    private var setupRows: some View {
        VStack(alignment: .leading, spacing: 18) {
            caption("check rows · arrived in ink, amber only for the fix")
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    CheckRow(name: "Heart rate", result: "Arrived 07:42", kind: .ok)
                    CheckRow(name: "HRV", result: "Not shared", kind: .expected)
                    CheckRow(name: "Breathing rate", result: "Last seen Mon", kind: .late)
                    CheckRow(name: "Resting heart rate", result: "Missing", kind: .fix)
                    CheckRow(name: "Workouts", result: "Checking…", kind: .checking)
                }
            }
            caption("capability rows · numbered steps · step rule")
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    CapabilityRow(title: "Heart rate", state: .yes)
                    CapabilityRow(title: "HRV", spokenTitle: "Heart rate variability", state: .no,
                                  detail: "Garmin keeps HRV in its own app.")
                    NumberedStep(number: 1, verbatim: "Open Garmin Connect → More → Settings → Connect Apps.", total: 3)
                    NumberedStep(number: 2, verbatim: "Under Available Apps, tap Apple Health.", total: 3)
                    NumberedStep(number: 3, verbatim: "Turn on all data types, then tap Allow.", total: 3)
                }
            }
            StepRule(step: 3, count: 6)
        }
    }

    private var tiles: some View {
        VStack(alignment: .leading, spacing: 18) {
            caption("selectable tiles · chosen and not")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach([("Garmin", "watch.analog"), ("Oura", "circle.circle"), ("Polar", "watch.analog"),
                         ("Amazfit (Zepp)", "watch.analog")], id: \.0) { title, symbol in
                    SelectableTile(symbol: symbol, title: title, isSelected: picked.contains(title)) {
                        if picked.contains(title) { picked.remove(title) } else { picked.insert(title) }
                    }
                }
            }
        }
    }

    private var trackerCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            caption("tracker setup card · Garmin")
            TrackerSetupCard(tracker: MockData.tracker("garmin"), later: {})
        }
    }

    private func caption(_ text: String) -> some View {
        Text(verbatim: text).font(.ryft(.caption)).foregroundStyle(Theme.textTertiary)
    }

    private static let legendRows = [("Recovery", Theme.recovery), ("Strain", Theme.metricStrain), ("Sleep", Theme.metricSleep)]

    static func clock(_ minutes: Int) -> String { String(format: "%d:%02d", minutes / 60, minutes % 60) }
}

#Preview("Nocturne · foundation") {
    NavigationStack {
        ScrollView {
            NocturneFoundationCatalog()
                .padding(Theme.Metrics.screenPadding)
        }
        .background(Theme.background)
    }
    .previewEnvironment()
}

#Preview("Nocturne · foundation · AX3") {
    NavigationStack {
        ScrollView {
            NocturneFoundationCatalog()
                .padding(Theme.Metrics.screenPadding)
        }
        .background(Theme.background)
    }
    .previewEnvironment()
    .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
