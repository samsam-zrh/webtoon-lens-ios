import SwiftUI
import WebtoonLensCore

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case webtoon
    case reader
    case series
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Accueil"
        case .webtoon: "Webtoon"
        case .reader: "Lecteur"
        case .series: "Series"
        case .settings: "Reglages"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "sparkles"
        case .webtoon: "safari"
        case .reader: "text.viewfinder"
        case .series: "book.closed"
        case .settings: "gearshape"
        }
    }
}

struct AppView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        WebtoonBrowserView()
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
