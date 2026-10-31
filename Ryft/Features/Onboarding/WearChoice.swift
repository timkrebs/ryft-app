import Foundation

/// "What do you wear?" as the user shapes it (design.md §D4.5, architecture.md §D4.6): the tiles they chose, and the
/// trackers Apple Health showed that they haven't confirmed yet. Pure, so the wizard, the Devices & sync sheet and
/// the tests share one set of rules.
///
/// - Detection pre-fills **once**, and only while no tile was touched: a selection never changes under a finger.
/// - A detected tile isn't a choice yet. Tapping it confirms it; a second tap clears it. The primary button saves
///   the choices and every detected tile still standing (pressing it confirms them all).
/// - "Just my iPhone" clears every other tile, detected ones too; any other tile clears it.
/// - Nothing is saved on detection alone: the caller saves `saved` when the user presses the button.
struct WearChoice: Equatable, Sendable {
    /// Tiles the user chose (or the account had chosen), in the order they were picked.
    private(set) var picked: [String]
    /// Found in Apple Health, not chosen and not touched yet: drawn as an outline with "Found in Apple Health".
    private(set) var detected: [String] = []
    /// A tile was tapped: detection never pre-fills after this.
    private(set) var touched = false
    /// Detection pre-filled already (it does so once).
    private(set) var seeded = false

    init(picked: [String] = []) {
        self.picked = picked
    }

    enum TileState: Equatable, Sendable { case chosen, detected, none }

    func state(of id: String) -> TileState {
        if picked.contains(id) { return .chosen }
        return detected.contains(id) ? .detected : .none
    }

    /// Detection's tracker ids (`SourceDetector.trackerIDs`): nil (not known, not asked, demo) or `[]` change
    /// nothing. Otherwise, once and only while untouched, the ids not already chosen become detected tiles. The iPhone
    /// alone is never pre-filled next to a choice (detection lists it only when nothing else wrote), and a choice of
    /// "Just my iPhone" isn't turned into a watch by detection either.
    mutating func seed(_ ids: [String]?) {
        guard !touched, !seeded, let ids, !ids.isEmpty else { return }
        seeded = true
        if picked.contains(TrackerSelectionStore.iPhone) { return }
        var found = ids.filter { !picked.contains($0) && $0 != "other" }
        if !picked.isEmpty || found.count > 1 { found.removeAll { $0 == TrackerSelectionStore.iPhone } }
        detected = found
    }

    /// A tile tapped. Returns whether other choices went ("Just my iPhone"), which VoiceOver announces.
    @discardableResult
    mutating func toggle(_ id: String) -> Bool {
        touched = true
        if let index = detected.firstIndex(of: id) {
            // Confirming a detected tile: it becomes a choice, without clearing anything.
            detected.remove(at: index)
            picked = TrackerSelectionStore.toggled(id, in: picked).picked
            return false
        }
        let next = TrackerSelectionStore.toggled(id, in: picked)
        picked = next.picked
        if id == TrackerSelectionStore.iPhone, picked == [TrackerSelectionStore.iPhone] {
            let cleared = next.cleared || !detected.isEmpty
            detected = []
            return cleared
        }
        return next.cleared
    }

    /// Detected tiles nobody touched yet: the screen says "RYFT found these…", and the button says "Confirm".
    var hasDetection: Bool { !detected.isEmpty }

    /// "Confirm" while detection pre-filled and nothing was touched; "Continue" (or the sheet's "Done") after the first
    /// change, and whenever nothing was detected.
    var confirms: Bool { seeded && !touched && hasDetection }

    /// What the button saves: the choices and the detected tiles still standing; "Just my iPhone" only on its own.
    var saved: [String] {
        let all = picked + detected.filter { !picked.contains($0) }
        let others = all.filter { $0 != TrackerSelectionStore.iPhone }
        return others.isEmpty ? all : others
    }

    /// The button needs something to save; a detection counts (pressing it confirms them).
    var canSave: Bool { !saved.isEmpty }
}
