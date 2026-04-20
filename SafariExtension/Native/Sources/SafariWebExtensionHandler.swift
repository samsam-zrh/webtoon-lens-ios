import Foundation
import SafariServices
import UIKit
import WebtoonLensCore

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        Task {
            do {
                let message = try Self.decodeMessage(from: context)
                let response = try await translate(message)
                try Self.complete(context, response: response)
            } catch {
                let response = SafariTranslateImageResponse(
                    ok: false,
                    imageHash: nil,
                    segments: [],
                    durationMilliseconds: 0,
                    error: error.localizedDescription
                )
                try? Self.complete(context, response: response)
            }
        }
    }

    private func translate(_ message: SafariTranslateImageMessage) async throws -> SafariTranslateImageResponse {
        guard message.type == "translateImage" else {
            throw SafariExtensionError.unsupportedMessage
        }

        let imageData = try await Self.loadImageData(from: message.imageURL)
        guard let image = UIImage(data: imageData) else {
            throw SafariExtensionError.invalidImage
        }

        let settings = SharedSettingsStore.shared
        let client: TranslationClientProtocol = if let backendURL = settings.backendBaseURL {
            WebtoonTranslationClient(baseURL: backendURL)
        } else {
            LocalPreviewTranslationClient()
        }

        let pipeline = WebtoonTranslationPipeline(client: client)
        let result = try await pipeline.translate(
            image: image,
            imageData: imageData,
            seriesID: message.seriesID,
            targetLanguage: message.targetLanguage ?? WebtoonLensConstants.defaultTargetLanguage,
            glossary: SharedGlossarySnapshotStore.loadInstructions(seriesID: message.seriesID),
            style: settings.defaultStylePrompt
        )

        return SafariTranslateImageResponse(
            ok: true,
            imageHash: result.imageHash,
            segments: result.segments,
            durationMilliseconds: result.durationMilliseconds,
            error: nil
        )
    }

    private static func decodeMessage(from context: NSExtensionContext) throws -> SafariTranslateImageMessage {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let userInfo = item.userInfo,
              let rawMessage = userInfo[SFExtensionMessageKey] else {
            throw SafariExtensionError.missingMessage
        }

        let data = try JSONSerialization.data(withJSONObject: rawMessage)
        return try JSONDecoder().decode(SafariTranslateImageMessage.self, from: data)
    }

    private static func complete(_ context: NSExtensionContext, response: SafariTranslateImageResponse) throws {
        let data = try JSONEncoder().encode(response)
        let object = try JSONSerialization.jsonObject(with: data)
        let item = NSExtensionItem()
        item.userInfo = [SFExtensionMessageKey: object]
        context.completeRequest(returningItems: [item])
    }

    private static func loadImageData(from value: String) async throws -> Data {
        if value.hasPrefix("data:"), let commaIndex = value.firstIndex(of: ",") {
            let encoded = String(value[value.index(after: commaIndex)...])
            guard let data = Data(base64Encoded: encoded) else {
                throw SafariExtensionError.invalidImage
            }
            return data
        }

        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased()) else {
            throw SafariExtensionError.unsupportedImageURL
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 8
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw SafariExtensionError.imageDownloadFailed
        }
        return data
    }
}

private struct SafariTranslateImageMessage: Codable {
    var type: String
    var imageURL: String
    var pageURL: String?
    var naturalWidth: Double?
    var naturalHeight: Double?
    var seriesID: String?
    var targetLanguage: String?
}

private struct SafariTranslateImageResponse: Codable {
    var ok: Bool
    var imageHash: String?
    var segments: [TranslatedSegmentPayload]
    var durationMilliseconds: Int
    var error: String?
}

private enum SafariExtensionError: Error, LocalizedError {
    case missingMessage
    case unsupportedMessage
    case unsupportedImageURL
    case imageDownloadFailed
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .missingMessage:
            return "Message Safari manquant."
        case .unsupportedMessage:
            return "Message Safari non pris en charge."
        case .unsupportedImageURL:
            return "URL d'image non prise en charge."
        case .imageDownloadFailed:
            return "Impossible de telecharger l'image."
        case .invalidImage:
            return "Image invalide."
        }
    }
}
