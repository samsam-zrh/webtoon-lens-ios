import AppIntents
import Observation
import SwiftData
import SwiftUI
import WebtoonLensCore

@main
struct WebtoonLensApp: App {
    @State private var appModel = AppModel()

    init() {
        WebtoonLensShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            AppView()
                .environment(appModel)
                .modelContainer(for: [
                    SeriesProfile.self,
                    TermMemoryEntry.self,
                    TranslationJob.self,
                    TranslatedSegment.self,
                    GlossaryVersion.self
                ])
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var selectedTab: AppTab = .home
    var handoffRefreshToken = UUID()

    func routeForPendingHandoffs() {
        if SharedHandoffStore.hasPendingImage {
            selectedTab = .reader
            handoffRefreshToken = UUID()
        }

        if SharedHandoffStore.consumeOpenLastTranslationRequest() {
            selectedTab = .reader
        }
    }
}
