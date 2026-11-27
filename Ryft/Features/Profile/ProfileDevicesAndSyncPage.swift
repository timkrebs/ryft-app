import SwiftUI

/// Devices & sync includes the tracker setup when it is enabled, or starts with RYFT's Apple Health access.
struct ProfileDevicesAndSyncPage: View {
    @Environment(ScreenModels.self) private var screens

    var body: some View {
        let model = screens.profile
        let facts = ProfileRowFacts(model, journalLive: false, bedtimeEnabled: false)
        let sections = ProfilePage.sections(.devicesAndSync, facts)
        if facts.devicesEnabled {
            DevicesAndSyncView(model: model.devices, placement: .pushed) {
                ProfileSyncStatusTile()
                    .padding(.bottom, GroupedListSpec.groupSpacing)
            } extra: {
                ProfileSyncSections(sections: sections)
                    .padding(.top, GroupedListSpec.groupSpacing)
            }
        } else {
            SubpageScaffold(Text("Devices & sync", comment: "Title of Profile's Devices and sync page.")) {
                VStack(alignment: .leading, spacing: GroupedListSpec.groupSpacing) {
                    ProfileSyncStatusTile()
                    if let health = sections.first(where: { $0.id == .healthAccess }) {
                        ProfilePageCard(section: health)
                    }
                    ProfileSyncSections(sections: sections)
                    if let details = sections.first(where: { $0.id == .syncDetails }) {
                        ProfilePageCard(section: details)
                    }
                }
            }
            .analyticsScreen(.devicesAndSync)
        }
    }
}

/// The sync, Apple Health writes and Advanced cards shared by both versions of Devices & sync.
struct ProfileSyncSections: View {
    let sections: [ProfilePage.Section]

    @Environment(ScreenModels.self) private var screens

    var body: some View {
        VStack(alignment: .leading, spacing: GroupedListSpec.groupSpacing) {
            ForEach(sections.filter { $0.id != .healthAccess && $0.id != .syncDetails }) { section in
                ProfilePageCard(section: section)
            }
            #if DEBUG
            ProfileDeveloperGroup(model: screens.profile)
            #endif
        }
    }
}

// MARK: - previews (dark; default and AX3)

#if DEBUG
#Preview("Profile · Devices & sync") { ProfilePreview.page(.signedIn, route: .devices) }
#Preview("Profile · Devices & sync · AX3") { ProfilePreview.page(.signedIn, route: .devices, ax3: true) }
#Preview("Profile · Devices & sync · Apple Health") {
    ProfilePreview.page(.signedIn, route: .devices, devicesEnabled: false)
}
#Preview("Profile · Devices & sync · Apple Health · AX3") {
    ProfilePreview.page(.signedIn, route: .devices, devicesEnabled: false, ax3: true)
}
#endif
