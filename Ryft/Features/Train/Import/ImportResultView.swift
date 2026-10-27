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
        // The result is shown: without refused items the resume row goes; with them (I4) it stays until Done.
        .task(id: [job?.isFinished, job?.hasRejected]) { model.resultShown() }
        .alert(Text("Discard the saved import?", comment: "Training import S2: the confirmation's title."),
               isPresented: $model.confirmsDiscardJob) {
            Button(role: .destructive) {
                model.discardJob()
            } label: {
                Text("Discard")
            }
            .accessibilityIdentifier("import.discardJob.confirm")
            Button(role: .cancel) {} label: { Text("Cancel") }
        } message: {
            Text("Nothing more is uploaded from it. Anything already imported stays in RYFT. The file itself is not changed.",
                 comment: "Training import S2: what discarding a saved import does.")
        }
        .toolbar {
            // I3, I4: Done is the trailing text button; Close (leading) stays.
            if job?.isFinished == true {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        model.done()
                    } label: {
                        Text("Done")
                    }
                    .accessibilityIdentifier("import.done")
                }
            }
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
                          systemImage: "wifi.slash", caption: ImportResultText.keptLimits)
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
                          caption: String(localized: "RYFT needs your answer before it sends anything. Your import is kept on this iPhone and continues afterwards.",
                                          comment: "Training import I8: a consent or invite step holds the upload.")
                              + " " + ImportResultText.keptLimits)
        case .notAvailable:
            // Calm and final for now: no error styling, no Try again. RYFT asks again when the app opens.
            header(String(localized: "Saved on this iPhone", comment: "Training import I9: importing isn't available for the account (403 import_not_enabled)."),
                   systemImage: "tray.and.arrow.down")
            Text("Your import is saved on this iPhone.", comment: "Training import I9.")
                .font(.ryft(.headline))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("import.result")
            line(String(localized: "Importing isn't available for your account right now. RYFT checks again when you open the app, and sends it once it is.",
                        comment: "Training import I9: not an error, nothing to do."))
            line(ImportResultText.keptLimits)
        case .held:
            // A 403 this build doesn't know: nothing for the user to answer, so no consent or gate words.
            header(String(localized: "Importing…", comment: "Training import I2."))
            progress(job, paused: true)
            InlineMessage(message: String(localized: "The upload is paused. RYFT will try again later.",
                                          comment: "Training import: a refusal with no step for the user (an unknown 403)."),
                          systemImage: "pause.circle",
                          details: job.lastFailure?.details,
                          caption: ImportResultText.keptLimits)
        case .needsAttention:
            // The platform refused everything in the last pass; the rest is still pending.
            header(String(localized: "Importing…", comment: "Training import I2."))
            progress(job, paused: true)
            InlineMessage(message: String(localized: "Some items weren't accepted, so the upload stopped.",
                                          comment: "Training import: the platform refused every request of the last pass."),
                          systemImage: "exclamationmark.circle",
                          details: job.lastFailure?.details,
                          retry: { await model.deps.uploader.tryAgain() },
                          caption: String(localized: "The rest of your import is kept on this iPhone. Try again to send it.",
                                          comment: "Training import: Try again sends the pending rest.")
                              + " " + ImportResultText.keptLimits,
                          identifier: "import.tryAgain")
            if job.hasRejected { rejected(job) }
        case .waitingForAccount:
            // A final 401 or an account deletion: the job goes with the account's data, so nothing resumes it.
            header(String(localized: "Importing…", comment: "Training import I2."))
            InlineMessage(message: String(localized: "This import can't continue.", comment: "Training import I7: signed out mid-upload."),
                          systemImage: "person.crop.circle.badge.exclamationmark",
                          details: job.lastFailure?.details,
                          caption: String(localized: "Sign in and pick the file again. Nothing is imported twice.",
                                          comment: "Training import I7: re-importing is safe, the ids are the same."))
        }
    }

    /// I5: "The upload paused." with a `Retry-After` countdown in text only.
    private func retrying(_ job: ImportJobStatus, at: Date?) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = at.map { max(0, Int($0.timeIntervalSince(context.date).rounded(.up))) }
            InlineMessage(message: String(localized: "The upload paused.", comment: "Training import I5."),
                          systemImage: "wifi.exclamationmark",
                          details: job.lastFailure?.details,
                          retry: { await model.deps.uploader.tryAgain() },
                          caption: (seconds.map { $0 > 0
                              ? String(localized: "Trying again in \($0) seconds", comment: "Training import I5: a Retry-After countdown.")
                              : String(localized: "Your import is kept on this iPhone. RYFT retries when the connection is back.",
                                       comment: "Training import I5.") }
                              ?? String(localized: "Your import is kept on this iPhone. RYFT retries when the connection is back.",
                                        comment: "Training import I5.")) + " " + ImportResultText.keptLimits,
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
                ForEach(job.planSummaries.filter { $0.state == .done }) { plan in
                    StatRow(title: "Plan", value: ImportResultText.plan(plan))
                }
                StatRow(title: "Workouts imported", value: "\(job.sessionsImported)")
                if job.leftAsIs > 0 {
                    StatRow(title: "Left as it is in RYFT", value: "\(job.leftAsIs)",
                            detail: String(localized: "You changed these in RYFT, so your version stays.",
                                           comment: "Training import I3: newer_on_server, why the file's version was not applied."))
                }
                if job.sessionsImported > 0 {
                    StatRow(title: "Sets imported", value: "\(job.setsDone)")
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
        if job.sessionsImported > 0 {
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
                ForEach(job.rejected) { ImportRejectionRow(item: $0) }
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
        case .paused(.notAvailable)?:
            ImportPrimaryButton(title: String(localized: "Done"), identifier: "import.done") { model.done() }
            discardJob
        case .paused(.gated)?:
            // The gate's sheet lives on the tab bar: close the cover so it can show; the import resumes once it's open.
            ImportPrimaryButton(title: String(localized: "Continue in RYFT",
                                              comment: "Training import I8: close the import so the consent or invite step can show."),
                                identifier: "import.continueInApp") {
                model.finish(.close)
            }
            discardJob
        case .paused(.offline)?, .paused(.retrying)?, .paused(.held)?, .paused(.needsAttention)?:
            discardJob
        case .paused(.waitingForAccount)?:
            ImportPrimaryButton(title: String(localized: "Done"), identifier: "import.done") { model.done() }
        default:
            EmptyView()
        }
    }

    /// S2: a saved or paused job can always be discarded, after a confirmation.
    private var discardJob: some View {
        Button {
            model.confirmsDiscardJob = true
        } label: {
            Text("Discard import", comment: "Training import S2: remove the saved import from this iPhone.")
                .font(.ryft(.callout))
                .foregroundStyle(Theme.alert)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("import.discardJob")
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
        if job.plansImported > 0 { parts.append(String(localized: "\(job.plansImported) plans", comment: "Training import: a count of plans.")) }
        if job.sessionsImported > 0 {
            parts.append(String(localized: "\(job.sessionsImported) workouts", comment: "Training import: a count of workouts."))
        }
        guard let first = parts.first else {
            if job.leftAsIs > 0 {
                return String(localized: "Nothing new: what's in the file is already in RYFT or stays as you changed it",
                              comment: "Training import I3: everything was already there or newer_on_server.")
            }
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

    /// "Upper/Lower · 6 weeks".
    static func plan(_ plan: ImportPlanSummary) -> String {
        ([plan.name] + [plan.weeks.map { String(localized: "\($0) weeks") }].compactMap { $0 }).joined(separator: " · ")
    }

    /// What "kept on this iPhone" means (privacy S2): how long, and what removes it.
    static var keptLimits: String {
        String(localized: "Kept on this iPhone for up to 30 days. Signing out removes it.",
               comment: "Training import: the limits of a saved import (TrainImportUploader.retention, the sign-out wipe).")
    }

    /// "67 percent, 8 of 12 workouts".
    static func progressValue(_ job: ImportJobStatus) -> String {
        let percent = Int((job.progress * 100).rounded())
        let workouts = String(localized: "\(job.sessions.done) of \(job.sessions.total) workouts", comment: "Training import I2: progress.")
        return String(localized: "\(percent) percent, \(workouts)", comment: "Training import, VoiceOver: the progress value.")
    }

    /// A refused item's reason in plain words.
    static func reason(_ item: ImportItemSummary) -> String { ImportRejectionText.reason(item) }
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

#Preview("Step 6 · not available · light · AX5") {
    NavigationStack {
        ImportResultView(model: ImportMockData.flow(.result, uploader: ImportMockData.uploader(MockTrainImport.savedOnPhone)))
    }
    .previewEnvironment(scheme: .light)
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Step 6 · left as it is · dark") {
    NavigationStack { ImportResultView(model: ImportMockData.flow(.result, uploader: ImportMockData.uploader(MockTrainImport.leftAsIsDone))) }
        .previewEnvironment()
}

#Preview("Step 6 · left as it is · light · AX5") {
    NavigationStack { ImportResultView(model: ImportMockData.flow(.result, uploader: ImportMockData.uploader(MockTrainImport.leftAsIsDone))) }
        .previewEnvironment(scheme: .light)
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Step 6 · rejected by reason · dark") {
    NavigationStack { ImportResultView(model: ImportMockData.flow(.result, uploader: ImportMockData.uploader(MockTrainImport.mixedRejections))) }
        .previewEnvironment()
}

#Preview("Step 6 · rejected by reason · light · AX5") {
    NavigationStack { ImportResultView(model: ImportMockData.flow(.result, uploader: ImportMockData.uploader(MockTrainImport.mixedRejections))) }
        .previewEnvironment(scheme: .light)
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Step 6 · waiting for consent · dark") {
    NavigationStack {
        ImportResultView(model: ImportMockData.flow(.result, uploader: ImportMockData.uploader(
            MockTrainImport.status(.paused(.gated(.gate(.consentRequired)))))))
    }
    .previewEnvironment()
}

#Preview("Step 6 · held · dark") {
    NavigationStack { ImportResultView(model: ImportMockData.flow(.result, uploader: ImportMockData.uploader(
        MockTrainImport.status(.paused(.held))))) }
        .previewEnvironment()
}

#Preview("Step 6 · needs attention · light") {
    NavigationStack { ImportResultView(model: ImportMockData.flow(.result, uploader: ImportMockData.uploader(
        MockTrainImport.status(.paused(.needsAttention), rejected: 3)))) }
        .previewEnvironment(scheme: .light)
}

#Preview("Step 6 · signed out mid-upload · light") {
    NavigationStack {
        ImportResultView(model: ImportMockData.flow(.result, uploader: ImportMockData.uploader(
            MockTrainImport.status(.paused(.waitingForAccount)))))
    }
    .previewEnvironment(scheme: .light)
}
#endif
