import AppIntents
import Foundation
import WebtoonLensCore

struct TranslateScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Traduire ce webtoon"
    static var description = IntentDescription("Recoit une capture d'ecran et l'ouvre dans Webtoon Lens pour OCR et traduction.")
    static var openAppWhenRun = true

    @Parameter(title: "Capture d'ecran")
    var screenshot: IntentFile

    func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = try SharedHandoffStore.savePendingImage(
            data: screenshot.data,
            filename: screenshot.filename.isEmpty ? "shortcut.png" : screenshot.filename
        )

        return .result(dialog: "Capture recue. Webtoon Lens va l'analyser.")
    }
}

struct OpenLastTranslationIntent: AppIntent {
    static var title: LocalizedStringResource = "Ouvrir la derniere traduction"
    static var description = IntentDescription("Ouvre Webtoon Lens sur le dernier resultat de traduction.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        SharedHandoffStore.requestOpenLastTranslation()
        return .result(dialog: "Ouverture du lecteur Webtoon Lens.")
    }
}
