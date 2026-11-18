import Foundation
import Testing
@testable import Ryft

/// NOCTURNE_STYLE §1, plan.md criterion 3: the app is dark in every context, whatever the system setting, and has no
/// appearance setting. The root's `.preferredColorScheme(.dark)` covers SwiftUI; the Info.plist key covers the rest.
@Suite("Dark only")
struct DarkOnlyTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard }

    /// `UIUserInterfaceStyle` keeps the launch screen, alerts, share sheets and UIKit's chrome dark, before SwiftUI's
    /// first frame and outside its hierarchy. Reads the built app's Info.plist (the test host).
    @Test func infoPlistForcesDark() {
        #expect(Bundle.main.infoDictionary?["UIUserInterfaceStyle"] as? String == "Dark",
                "Ryft/Info.plist: UIUserInterfaceStyle must be Dark")
    }

    /// An earlier version stored `appearance` (dark, light or system). Nothing reads it any more: Settings loads as usual
    /// and holds no appearance of its own.
    @Test("A stored appearance is ignored", arguments: ["light", "system", "dark"])
    func aStoredAppearanceIsIgnored(_ stored: String) {
        let d = defaults()
        d.set(stored, forKey: "appearance")
        d.set(false, forKey: "demoMode")
        let settings = Settings(defaults: d)
        #expect(settings.demoMode == false)
        let labels = Mirror(reflecting: settings).children.compactMap(\.label)
        #expect(!labels.isEmpty, "Mirror sees Settings' stored properties")
        #expect(!labels.contains { $0.localizedCaseInsensitiveContains("appearance") },
                "Settings has an appearance again: \(labels)")
    }

    /// The comment on `clearPerUserState`: demo mode, the training preferences and the device ID stay on log-out.
    @Test func logOutKeepsTheDevicePreferences() {
        let d = defaults()
        let settings = Settings(defaults: d)
        settings.demoMode = true
        settings.jumpToNextExercise = false
        settings.sessionLayout = .list
        settings.lastSync = .now
        settings.healthIntroDone = true
        let device = settings.deviceId
        settings.clearPerUserState()
        #expect(settings.demoMode)
        #expect(settings.jumpToNextExercise == false)
        #expect(settings.sessionLayout == .list)
        #expect(settings.deviceId == device)
        #expect(settings.lastSync == nil)
        #expect(settings.healthIntroDone == false)
        let reloaded = Settings(defaults: d)
        #expect(reloaded.demoMode && reloaded.jumpToNextExercise == false && reloaded.sessionLayout == .list)
        #expect(reloaded.deviceId == device)
    }
}
