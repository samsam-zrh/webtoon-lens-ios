import AppIntents

struct WebtoonLensShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .teal

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TranslateScreenshotIntent(),
            phrases: [
                "Traduire ce webtoon avec \(.applicationName)",
                "Lire ce webtoon avec \(.applicationName)"
            ],
            shortTitle: "Traduire webtoon",
            systemImageName: "text.viewfinder"
        )

        AppShortcut(
            intent: OpenLastTranslationIntent(),
            phrases: [
                "Ouvrir la derniere traduction dans \(.applicationName)",
                "Reprendre ma lecture dans \(.applicationName)"
            ],
            shortTitle: "Derniere traduction",
            systemImageName: "clock.arrow.circlepath"
        )
    }
}
