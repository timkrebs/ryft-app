import SwiftUI

/// Step 6 (ui.md §8.2): progress and the result, from the account's import job. Never a spinner or a blocking
/// overlay: a thin determinate bar and counts. Close leaves the screen and the import continues; a failed item is a
/// word with its reason and one Retry.
struct ImportResultView: View {
    @Bindable var model: ImportFlowModel

    @State private var showsRejected = false
    @State private var showsDuplicates = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var job: ImportJobStatus? { model.job }

    var body: some View {
        ImportStepScaffold(model: model, step: .result) {
            if model.blockedByRunningJob, job?.isFinished == false {
                ImportNoteLine(systemImage: "info.circle", text: String(
                    localized: "An import is in progress. Finish it before starting another.",
                    comment: "Training import: one import at a time."))
            }
            state
        } bottom: {
            buttons
        }
        .onChange(of: job?.isFinished) { _, finished in
            guard finished == true, let job else { return }
            model.deps.announce(String(localized: "Import finished. \(ImportResultText.sentence(job))",
                                       comment: "Training import, VoiceOver: the result as it arrives."))
        }
    }

    // MARK: States

    @ViewBuilder
    private var state: some View {
        switch job?.phase {
        case nil, .preparing?:
            header(String(localized: "Getting ready", comment: "Training import I1."))
            VStack(alignment: .leading, spacing: 8) {
                if let pending = job?.exercises.pending, pending > 0 {
                    line(String(localized: "Creating \(pending) custom exercises…", comment: "Training import I1."))
                }
                line(String(localized: "Preparing your import…", comment: "Training import I1."))
                ImportProgressBar(fraction: 0, showsFill: false)
            }
        case .uploading?:
            if let job { uploading(job) }
        case let .paused(pause)?:
            if let job { paused(job, pause) }
        case .finished?:
            if let job { finished(job) }
        }
    }

    private func header(_ text: String, systemImage: String? = nil) -> some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage).foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
            }
            Text(verbatim: text)
                .font(.ryft(.title))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private func line(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.ryft(.callout))
            .monospacedDigit()
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// I2: the bar fills by items; "8 of 12 workouts".
    private func uploading(_ job: ImportJobStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(String(localized: "Importing…", comment: "Training import I2."))
            progress(job, paused: false)
            line(String(localized: "You can close this. The import continues while RYFT is open and picks up where it stopped.",
                        comment: "Training import I2."))
        }
    }

    private func progress(_ job: ImportJobStatus, paused: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ImportProgressBar(fraction: job.progress, isPaused: paused)
            if job.sessions.total > 0 {
                line(String(localized: "\(job.sessions.done) of \(job.sessions.total) workouts", comment: "Training import I2: progress."))
            }
            if job.plans.total > 0, job.plans.pending == 0 {
                line(String(localized: "Plan: done", comment: "Training import I2: the plan is uploaded."))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Import progress", comment: "Training import, VoiceOver: the progress bar."))
        .accessibilityValue(Text(verbatim: ImportResultText.progressValue(job)))
    }

    @ViewBuilder
    private func paused(_ job: ImportJobStatus, _ pause: ImportPause) -> some View {
        switch pause {
        case .offline:
            header(String(localized: "Importing…", comment: "Training import I2."))
            progress(job, paused: true)
            InlineMessage(message: String(localized: "You're offline. Your import is kept on this iPhone and continues when you're back online.",
                                          comment: "Training import I6."),
                          systemImage: "wifi.slash")
        case let .retrying(at):
            header(String(localized: "Importing…", comment: "Training import I2."))
            progress(job, paused: true)
            retrying(job, at: at)
        case .gated:
            header(String(localized: "Importing…", comment: "Training import I2."))
            progress(job, paused: true)
            InlineMessage(message: String(localized: "The upload paused.", comment: "Training import I5."),
                          systemImage: "hand.raised",
                          details: job.lastFailure?.details,
                          caption: String(localized: "Your import is kept on this iPhone. RYFT retries when the connection is back.",
                                          comment: "Training import I5."))
        case .notAvailable:
            header(String(localized: "Ready", comment: "Training import I9."))
            Text("Your import is saved on this iPhone.", comment: "Training import I9.")
                .font(.ryft(.headline))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityIdentifier("import.result")
            line(String(localized: "It uploads when importing is available for your account.", comment: "Training import I9."))
        case .waitingForAccount:
            header(String(localized: "Importing…", comment: "Training import I2."))
            InlineMessage(message: String(localized: "This import belongs to another account.", comment: "Training import I7."),
                          systemImage: "person.crop.circle.badge.exclamationmark")
        }
    }

    /// I5: "The upload paused." with a `Retry-After` countdown in text only.
    private func retrying(_ job: ImportJobStatus, at: Date?) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = at.map { max(0, Int($0.timeIntervalSince(context.date).rounded(.up))) }
            InlineMessage(message: String(localized: "The upload paused.", comment: "Training import I5."),
                          systemImage: "wifi.exclamationmark",
                          details: job.lastFailure?.details,
                          retry: { await model.deps.uploader.resume() },
                          caption: seconds.map { $0 > 0
                              ? String(localized: "Trying again in \($0) seconds", comment: "Training import I5: a Retry-After countdown.")
                              : String(localized: "Your import is kept on this iPhone. RYFT retries when the connection is back.",
                                       comment: "Training import I5.") }
                              ?? String(localized: "Your import is kept on this iPhone. RYFT retries when the connection is back.",
                                        comment: "Training import I5."),
                          identifier: "import.retry")
        }
    }

    /// I3 and I4: the sentence first, big, then the counts.
    @ViewBuilder
    private func finished(_ job: ImportJobStatus) -> some View {
        if job.hasRejected {
            header(String(localized: "Some items weren't imported", comment: "Training import I4."))
        } else {
            header(String(localized: "Done"), systemImage: "checkmark.circle")
        }
        Text(verbatim: ImportResultText.sentence(job))
            .font(.ryft(.headline))
            .monospacedDigit()
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("import.result")
        Card {
            VStack(alignment: .leading, spacing: 10) {
                if job.plans.done > 0 {
                    StatRow(title: "Plans", value: model.build?.plans.first(where: \.willBeSent).map { model.planName($0) }
                        ?? "\(job.plans.done)")
                }
                StatRow(title: "Workouts imported", value: "\(job.sessions.done)")
                if let sets = model.totals?.sets, job.sessions.done > 0 {
                    StatRow(title: "Sets imported", value: "\(sets)")
                }
                if job.skipped.skippedSets > 0 {
                    StatRow(title: "Sets skipped", value: "\(job.skipped.skippedSets)",
                            detail: String(localized: "No weight or reps.", comment: "Training import I3: why sets are skipped."))
                }
                if job.skipped.alreadyImported > 0 {
                    StatRow(title: "Already in RYFT", value: String(localized: "\(job.skipped.alreadyImported) workouts left as they were",
                                                                    comment: "Training import I3."))
                }
            }
        }
        if job.hasRejected { rejected(job) }
        if !job.duplicatesFound.isEmpty { duplicatesFound(job) }
        if job.sessions.done > 0 {
            Text("Past strain on these days is being recalculated. It may take a minute to show.",
                 comment: "Training import I3: after history was imported.")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func rejected(_ job: ImportJobStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            disclosure(String(localized: "Not imported (\(job.rejected.count))", comment: "Training import I4: the list's header."),
                       isOpen: $showsRejected)
            if showsRejected {
                ForEach(job.rejected) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: [item.date.map(Fmt.date), item.title].compactMap { $0 }.joined(separator: " · "))
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textPrimary)
                        Text(verbatim: ImportResultText.reason(item))
                            .font(.ryft(.caption))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let details = job.lastFailure?.details ?? job.rejected.compactMap(\.requestID).first.map({ "Request ID \($0)" }) {
                    InlineMessage(message: String(localized: "Rejected by the server", comment: "Training import I4: a reason."),
                                  systemImage: "exclamationmark.circle", details: details)
                }
            }
        }
    }

    private func duplicatesFound(_ job: ImportJobStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            disclosure(String(localized: "\(job.duplicatesFound.count) workouts looked like ones you already logged and were skipped",
                              comment: "Training import: duplicates found by the upload's own check."),
                       isOpen: $showsDuplicates)
            if showsDuplicates {
                ForEach(job.duplicatesFound) { item in
                    Text(verbatim: [item.date.map(Fmt.date), item.title].compactMap { $0 }.joined(separator: " · "))
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            ImportTextButton(title: String(localized: "Import these too", comment: "Training import: send the duplicates anyway."),
                             identifier: "import.importDuplicates") {
                Task { await model.importDuplicatesFound() }
            }
        }
    }

    private func disclosure(_ title: String, isOpen: Binding<Bool>) -> some View {
        Button {
            isOpen.wrappedValue.toggle()
        } label: {
            HStack {
                Text(verbatim: title)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(isOpen.wrappedValue ? 180 : 0))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOpen.wrappedValue ? Text("Expanded") : Text("Collapsed"))
    }

    // MARK: Buttons

    @ViewBuilder
    private var buttons: some View {
        if let name = model.waitingFileName(), job?.isFinished == true {
            ImportTextButton(title: String(localized: "Open the file you just received", comment: "Training import: a file arrived meanwhile (E9)."),
                             systemImage: "doc.text") {
                Task { await model.openReceivedFile() }
            }
            .accessibilityHint(Text(verbatim: name))
        }
        switch job?.phase {
        case .finished?:
            if let job, job.hasRejected {
                ImportPrimaryButton(title: String(localized: "Retry \(job.rejected.count)", comment: "Training import I4: send the failed items again."),
                                    identifier: "import.retryRejected") {
                    Task { await model.retryRejected() }
                }
            }
            if let job, job.plans.done > 0 {
                if !job.hasRejected {
                    ImportPrimaryButton(title: String(localized: "Open plan", comment: "Training import I3."), identifier: "import.openPlan") {
                        model.openPlan()
                    }
                }
                secondary(String(localized: "Open history", comment: "Training import I3."), identifier: "import.openHistory") {
                    model.openHistory()
                }
            } else if job?.hasRejected == false {
                ImportPrimaryButton(title: String(localized: "Open history", comment: "Training import I3."),
                                    identifier: "import.openHistory") {
                    model.openHistory()
                }
            }
            secondary(String(localized: "Done"), identifier: "import.done") { model.done() }
        case .paused(.notAvailable)?:
            ImportPrimaryButton(title: String(localized: "Done"), identifier: "import.done") { model.done() }
        case .paused(.waitingForAccount)?:
            secondary(String(localized: "Discard import", comment: "Training import I7."), identifier: "import.discardJob",
                      role: .destructive) {
                model.discardJob()
            }
        default:
            EmptyView()
        }
    }

    private func secondary(_ title: String, identifier: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Text(verbatim: title)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(TealButtonStyle(prominent: false))
        .foregroundStyle(role == .destructive ? Theme.alert : Theme.accent)
        .accessibilityIdentifier(identifier)
    }
}

/// Step 6's words (ui.md §8.2, §11).
enum ImportResultText {
    /// "Imported 1 plan and 12 workouts · 3 sets skipped (no weight or reps)", and the I4 and nothing-new variants.
    static func sentence(_ job: ImportJobStatus) -> String {
        var parts: [String] = []
        if job.plans.done > 0 { parts.append(String(localized: "\(job.plans.done) plans", comment: "Training import: a count of plans.")) }
        if job.sessions.done > 0 {
            parts.append(String(localized: "\(job.sessions.done) workouts", comment: "Training import: a count of workouts."))
        }
        guard let first = parts.first else {
            return String(localized: "Nothing new: everything in the file was already in RYFT", comment: "Training import I3.")
        }
        let what = parts.count > 1
            ? String(localized: "\(first) and \(parts[1])", comment: "Training import: two counts, e.g. 1 plan and 12 workouts.")
            : first
        var sentence = String(localized: "Imported \(what)", comment: "Training import I3: the result, e.g. Imported 1 plan and 12 workouts.")
        let failed = job.sessions.rejected + job.sessions.blocked
        if failed > 0 {
            sentence += " · " + String(localized: "\(failed) workouts not imported", comment: "Training import I4.")
        } else if job.skipped.skippedSets > 0 {
            sentence += " · " + String(localized: "\(job.skipped.skippedSets) sets skipped (no weight or reps)",
                                       comment: "Training import I3: sets that weren't imported.")
        }
        return sentence
    }

    /// "67 percent, 8 of 12 workouts".
    static func progressValue(_ job: ImportJobStatus) -> String {
        let percent = Int((job.progress * 100).rounded())
        let workouts = String(localized: "\(job.sessions.done) of \(job.sessions.total) workouts", comment: "Training import I2: progress.")
        return String(localized: "\(percent) percent, \(workouts)", comment: "Training import, VoiceOver: the progress value.")
    }

    /// A refused item's reason in plain words.
    static func reason(_ item: ImportItemSummary) -> String {
        if item.blocked {
            return String(localized: "The exercise wasn't found", comment: "Training import I4: a reason.")
        }
        return item.reason ?? String(localized: "Rejected by the server", comment: "Training import I4: a reason.")
    }
}

#if DEBUG
#Preview("Step 6 · getting ready · dark") {
    NavigationStack { ImportResultView(model: ImportMockData.flow(.result, uploader: ImportMockData.uploader(nil))) }
        .previewEnvironment()
}

#Preview("Step 6 · uploading 8 of 12 · light · AX3") {
    NavigationStack { ImportResultView(model: ImportMockData.flow(.result, uploader: ImportMockData.uploader(MockTrainImport.uploading))) }
        .previewEnvironment(scheme: .light)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Step 6 · done · dark") {
    NavigationStack { ImportResultView(model: ImportMockData.flow(.result, uploader: ImportMockData.uploader(MockTrainImport.done))) }
        .previewEnvironment()
}

#Preview("Step 6 · done · light · AX3") {
    NavigationStack { ImportResultView(model: ImportMockData.flow(.result, uploader: ImportMockData.uploader(MockTrainImport.done))) }
        .previewEnvironment(scheme: .light)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Step 6 · partly done · light") {
    NavigationStack {
        ImportResultView(model: ImportMockData.flow(.result, uploader: ImportMockData.uploader(MockTrainImport.partlyDone)))
    }
    .previewEnvironment(scheme: .light)
}

#Preview("Step 6 · paused, retry in 30 s · dark") {
    NavigationStack { ImportResultView(model: ImportMockData.flow(.result, uploader: ImportMockData.uploader(MockTrainImport.retrying))) }
        .previewEnvironment()
}

#Preview("Step 6 · offline · light") {
    NavigationStack { ImportResultView(model: ImportMockData.flow(.result, uploader: ImportMockData.uploader(MockTrainImport.offline))) }
        .previewEnvironment(scheme: .light)
}

#Preview("Step 6 · saved on this iPhone · dark") {
    NavigationStack {
        ImportResultView(model: ImportMockData.flow(.result, uploader: ImportMockData.uploader(MockTrainImport.savedOnPhone)))
    }
    .previewEnvironment()
}

#Preview("Step 6 · another account · light") {
    NavigationStack {
        ImportResultView(model: ImportMockData.flow(.result, uploader: ImportMockData.uploader(
            MockTrainImport.status(.paused(.waitingForAccount)))))
    }
    .previewEnvironment(scheme: .light)
}
#endif
