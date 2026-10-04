import AppIntents
import Observation
import SwiftData
import SwiftUI
import WebtoonLensCore

@main
struct WebtoonLensApp: App {
    @State private var appModel = AppModel()
    private let modelContainer: ModelContainer

    init() {
        WebtoonLensShortcuts.updateAppShortcutParameters()
        let schema = Schema([SeriesProfile.self, TermMemoryEntry.self, TranslationJob.self, TranslatedSegment.self, GlossaryVersion.self])
        #if DEBUG && targetEnvironment(simulator)
        let inMemory = ProcessInfo.processInfo.environment["WEBTOON_LENS_TEST_PREFERENCES"]?.hasPrefix("WebtoonLensV2.UI-") == true
        #else
        let inMemory = false
        #endif
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)])
        } catch {
            fatalError("Impossible d'ouvrir le stockage V2 : \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppView()
                .environment(appModel)
                .modelContainer(modelContainer)
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var selectedTab: AppTab = .webtoon
    var handoffRefreshToken = UUID()
    var readingChromeCollapsed = false
    var pendingHistoryURL: URL?

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
