#if canImport(WebKit)
import Foundation
import WebKit
#if canImport(UIKit)
import UIKit
public typealias ViewportSnapshotImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias ViewportSnapshotImage = NSImage
#endif

@MainActor
public enum WebKitViewportCapture {
    public static func document(in webView: WKWebView, world: WKContentWorld) async throws -> BrowserDocumentState {
        try Task.checkCancellation()
        let document: BrowserDocumentState = try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript("JSON.stringify(window.WebtoonLensV2.state())", in: nil, in: world) { result in
                switch result {
                case .failure(let error):
                    continuation.resume(throwing: error)
                case .success(let value):
                    do {
                        guard let string = value as? String else { throw BrowserCaptureError.invalidBridge }
                        let document = try JSONDecoder().decode(BrowserDocumentState.self, from: Data(string.utf8))
                        continuation.resume(returning: document)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
        try Task.checkCancellation()
        return document
    }

    public static func snapshot(in webView: WKWebView, configuration: WKSnapshotConfiguration) async throws -> ViewportSnapshotImage {
        try Task.checkCancellation()
        let image: ViewportSnapshotImage = try await withCheckedThrowingContinuation { continuation in
            webView.takeSnapshot(with: configuration) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: BrowserCaptureError.unreadableSnapshot)
                }
            }
        }
        try Task.checkCancellation()
        return image
    }
}
#endif
