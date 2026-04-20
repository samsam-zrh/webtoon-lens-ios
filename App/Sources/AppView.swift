import SwiftUI
import WebtoonLensCore

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case reader
    case series
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Accueil"
        case .reader: "Lecteur"
        case .series: "Series"
        case .settings: "Reglages"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "sparkles"
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
        @Bindable var appModel = appModel

        TabView(selection: $appModel.selectedTab) {
            NavigationStack {
                OnboardingView()
                    .navigationTitle("Webtoon Lens")
            }
            .tabItem { Label(AppTab.home.title, systemImage: AppTab.home.systemImage) }
            .tag(AppTab.home)

            NavigationStack {
                ReaderView()
                    .navigationTitle("Lecteur")
            }
            .tabItem { Label(AppTab.reader.title, systemImage: AppTab.reader.systemImage) }
            .tag(AppTab.reader)

            NavigationStack {
                SeriesView()
                    .navigationTitle("Series")
            }
            .tabItem { Label(AppTab.series.title, systemImage: AppTab.series.systemImage) }
            .tag(AppTab.series)

            NavigationStack {
                SettingsView()
                    .navigationTitle("Reglages")
            }
            .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage) }
            .tag(AppTab.settings)
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
