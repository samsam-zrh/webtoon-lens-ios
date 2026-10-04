import SwiftUI
import WebtoonLensCore

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case webtoon
    case reader
    case series
    case settings
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Accueil"
        case .webtoon: "Webtoon"
        case .reader: "Lecteur"
        case .series: "Series"
        case .settings: "Reglages"
        case .history: "Historique"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "sparkles"
        case .webtoon: "safari"
        case .reader: "text.viewfinder"
        case .series: "book.closed"
        case .settings: "gearshape"
        case .history: "clock"
        }
    }
}

struct AppView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var appModel = appModel
        TabView(selection: $appModel.selectedTab) {
            WebtoonBrowserView()
                .tabItem { Label("Lecture", systemImage: "book") }
                .tag(AppTab.webtoon)
                .toolbar(appModel.readingChromeCollapsed ? .hidden : .visible, for: .tabBar)
            NavigationStack { ReadingHistoryView() }
                .tabItem { Label("Historique", systemImage: "clock") }
                .tag(AppTab.history)
        }
        .fullScreenCover(isPresented: Binding(
            get: { appModel.selectedTab == .reader },
            set: { if !$0 { appModel.selectedTab = .webtoon } }
        )) {
            NavigationStack {
                ReaderView().navigationTitle("Lecteur")
                    .toolbar { Button("Fermer") { appModel.selectedTab = .webtoon } }
            }
        }
        .task {
            appModel.routeForPendingHandoffs()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                appModel.routeForPendingHandoffs()
            }
        }
    }
}
