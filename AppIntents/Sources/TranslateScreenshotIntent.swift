import AppIntents
import Foundation
import WebtoonLensCore

struct TranslateScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Traduire ce webtoon V2"
    static var description = IntentDescription("Recoit une capture choisie et l'ouvre dans Webtoon Lens V2 pour OCR local et traduction apres consentement.")
    static var openAppWhenRun = true

    @Parameter(title: "Capture d'ecran")
    var screenshot: IntentFile

    func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = try SharedHandoffStore.savePendingImage(
            data: screenshot.data,
            filename: screenshot.filename.isEmpty ? "shortcut.png" : screenshot.filename
        )

        return .result(dialog: "Capture recue dans Webtoon Lens V2.")
    }
}

struct OpenLastTranslationIntent: AppIntent {
    static var title: LocalizedStringResource = "Ouvrir la derniere traduction"
    static var description = IntentDescription("Ouvre Webtoon Lens V2 sur le dernier resultat de traduction.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        SharedHandoffStore.requestOpenLastTranslation()
        return .result(dialog: "Ouverture du lecteur Webtoon Lens V2.")
    }
}
