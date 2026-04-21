import SwiftData
import SwiftUI
import UIKit
import WebKit
import WebtoonLensCore

struct WebtoonBrowserView: View {
    @Query(sort: \SeriesProfile.updatedAt, order: .reverse) private var profiles: [SeriesProfile]
    @Query(sort: \TermMemoryEntry.updatedAt, order: .reverse) private var terms: [TermMemoryEntry]

    @State private var address = "https://"
    @State private var loadedURL: URL?
    @State private var selectedSeriesID = ""
    @State private var isAutoTranslateEnabled = true
    @State private var isTranslating = false
    @State private var status = "Colle une URL webtoon, puis lis directement ici."

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    TextField("https://site-webtoon.com/episode", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.go)
                        .onSubmit(loadAddress)

                    Button("Ouvrir", action: loadAddress)
                        .buttonStyle(.borderedProminent)
                }

                HStack(spacing: 10) {
                    if !profiles.isEmpty {
                        Picker("Serie", selection: $selectedSeriesID) {
                            Text("Aucune").tag("")
                            ForEach(profiles) { profile in
                                Text(profile.title).tag(profile.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Toggle("Auto", isOn: $isAutoTranslateEnabled)
                        .labelsHidden()

                    Button {
                        NotificationCenter.default.post(name: .webtoonLensTranslateVisibleImages, object: nil)
                    } label: {
                        if isTranslating {
                            ProgressView()
                        } else {
                            Label("Traduire", systemImage: "text.viewfinder")
                        }
                    }
                    .buttonStyle(.bordered)
                }

                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background(.thinMaterial)

            WebtoonWebView(
                url: loadedURL,
                autoTranslate: isAutoTranslateEnabled,
                translateRequest: makeTranslateRequest,
                onStatusChange: { status = $0 },
                onTranslatingChange: { isTranslating = $0 }
            )
        }
        .onAppear {
            if selectedSeriesID.isEmpty, let first = profiles.first {
                selectedSeriesID = first.id
            }
        }
    }

    private func loadAddress() {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let value = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: value) else {
            status = "URL invalide."
            return
        }
        loadedURL = url
        address = value
        status = "Page chargee. Traduction des images visibles activee."
    }

    private func makeTranslateRequest(_ imageRequest: WebImageRequest) async throws -> WebImageTranslationPayload {
        let data = try await WebImageLoader.loadData(from: imageRequest.imageURL)
        guard let image = UIImage(data: data) else {
            throw WebtoonBrowserError.invalidImage
        }

        let settings = SharedSettingsStore.shared
        let client: TranslationClientProtocol = if let backendURL = settings.backendBaseURL {
            WebtoonTranslationClient(baseURL: backendURL)
        } else {
            LocalPreviewTranslationClient()
        }

        let activeProfile = profiles.first { $0.id == selectedSeriesID }
        let activeTerms = selectedSeriesID.isEmpty ? terms : terms.filter { $0.seriesID == selectedSeriesID }
        let pipeline = WebtoonTranslationPipeline(client: client)
        let result = try await pipeline.translate(
            image: image,
            imageData: data,
            seriesID: activeProfile?.id,
            sourceLanguage: activeProfile?.sourceLanguage ?? WebtoonLensConstants.autoSourceLanguage,
            targetLanguage: activeProfile?.targetLanguage ?? WebtoonLensConstants.defaultTargetLanguage,
            glossary: GlossaryResolver.instructions(from: activeTerms),
            style: activeProfile?.stylePrompt ?? settings.defaultStylePrompt
        )

        return WebImageTranslationPayload(imageID: imageRequest.imageID, result: result)
    }
}

private struct WebtoonWebView: UIViewRepresentable {
    let url: URL?
    let autoTranslate: Bool
    let translateRequest: (WebImageRequest) async throws -> WebImageTranslationPayload
    let onStatusChange: (String) -> Void
    let onTranslatingChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.bridgeScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        ))
        configuration.userContentController.add(context.coordinator, name: "webtoonLensImage")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.installTranslateObserver()
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if let url, webView.url != url {
            webView.load(URLRequest(url: url))
        }
        webView.evaluateJavaScript("window.WebtoonLensNative && window.WebtoonLensNative.setAutoTranslate(\(autoTranslate ? "true" : "false"));")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: WebtoonWebView
        weak var webView: WKWebView?
        private var activeTasks: [String: Task<Void, Never>] = [:]
        private var observer: NSObjectProtocol?

        init(_ parent: WebtoonWebView) {
            self.parent = parent
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func installTranslateObserver() {
            guard observer == nil else { return }
            observer = NotificationCenter.default.addObserver(
                forName: .webtoonLensTranslateVisibleImages,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.webView?.evaluateJavaScript("window.WebtoonLensNative && window.WebtoonLensNative.scan();")
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onStatusChange("Page prete. Les images visibles seront traduites dans la page.")
            webView.evaluateJavaScript("window.WebtoonLensNative && window.WebtoonLensNative.setAutoTranslate(\(parent.autoTranslate ? "true" : "false"));")
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "webtoonLensImage",
                  let body = message.body as? [String: Any],
                  let request = WebImageRequest(body: body),
                  activeTasks[request.imageID] == nil else {
                return
            }

            activeTasks[request.imageID] = Task { [weak self] in
                await self?.translate(request)
            }
        }

        @MainActor
        private func translate(_ request: WebImageRequest) async {
            parent.onTranslatingChange(true)
            parent.onStatusChange("Traduction d'une image visible...")
            defer {
                activeTasks[request.imageID] = nil
                parent.onTranslatingChange(!activeTasks.isEmpty)
            }

            do {
                let payload = try await parent.translateRequest(request)
                try await render(payload)
                parent.onStatusChange("\(payload.result.segments.count) bulles posees sur la page.")
            } catch {
                parent.onStatusChange(error.localizedDescription)
                await markFailed(imageID: request.imageID, message: error.localizedDescription)
            }
        }

        @MainActor
        private func render(_ payload: WebImageTranslationPayload) async throws {
            guard let webView else { return }
            let data = try JSONEncoder().encode(payload)
            guard let json = String(data: data, encoding: .utf8) else { return }
            _ = try await webView.evaluateJavaScript("window.WebtoonLensNative.renderTranslation(\(json));")
        }

        @MainActor
        private func markFailed(imageID: String, message: String) async {
            let escaped = message
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: " ")
            _ = try? await webView?.evaluateJavaScript("window.WebtoonLensNative.markFailed('\(imageID)', '\(escaped)');")
        }
    }
}

private struct WebImageRequest: Sendable {
    let imageID: String
    let imageURL: String
    let pageURL: String

    init?(body: [String: Any]) {
        guard let imageID = body["imageID"] as? String,
              let imageURL = body["imageURL"] as? String else {
            return nil
        }
        self.imageID = imageID
        self.imageURL = imageURL
        self.pageURL = body["pageURL"] as? String ?? ""
    }
}

private struct WebImageTranslationPayload: Encodable {
    let imageID: String
    let result: TranslationResult
}

private enum WebImageLoader {
    static func loadData(from value: String) async throws -> Data {
        if value.hasPrefix("data:"), let commaIndex = value.firstIndex(of: ",") {
            let encoded = String(value[value.index(after: commaIndex)...])
            guard let data = Data(base64Encoded: encoded) else {
                throw WebtoonBrowserError.invalidImage
            }
            return data
        }

        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased()) else {
            throw WebtoonBrowserError.unsupportedImageURL
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw WebtoonBrowserError.imageDownloadFailed
        }
        return data
    }
}

private enum WebtoonBrowserError: Error, LocalizedError {
    case invalidImage
    case unsupportedImageURL
    case imageDownloadFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Image webtoon illisible."
        case .unsupportedImageURL:
            return "Image non accessible par l'app."
        case .imageDownloadFailed:
            return "Telechargement de l'image impossible."
        }
    }
}

extension Notification.Name {
    static let webtoonLensTranslateVisibleImages = Notification.Name("webtoonLensTranslateVisibleImages")
}

private extension WebtoonWebView {
    static let bridgeScript = """
    (() => {
      if (window.WebtoonLensNative) return;

      const states = new WeakMap();
      let autoTranslate = true;
      let timer = null;

      function stableId(image) {
        if (!image.dataset.webtoonLensId) {
          image.dataset.webtoonLensId = 'wl-' + Math.random().toString(36).slice(2) + Date.now().toString(36);
        }
        return image.dataset.webtoonLensId;
      }

      function imageURL(image) {
        return image.currentSrc || image.src || '';
      }

      function isCandidate(image) {
        const rect = image.getBoundingClientRect();
        const height = window.innerHeight || document.documentElement.clientHeight;
        const width = window.innerWidth || document.documentElement.clientWidth;
        return rect.bottom > -height && rect.top < height * 2 &&
          rect.right > 0 && rect.left < width &&
          rect.width >= 140 && rect.height >= 120 &&
          imageURL(image).length > 0;
      }

      function ensureOverlay(image) {
        let state = states.get(image);
        if (state && state.overlay) return state.overlay;

        const overlay = document.createElement('div');
        overlay.className = 'webtoon-lens-native-overlay';
        overlay.style.position = 'absolute';
        overlay.style.zIndex = '2147483647';
        overlay.style.pointerEvents = 'none';
        overlay.style.boxSizing = 'border-box';
        document.documentElement.appendChild(overlay);

        state = { status: 'new', overlay };
        states.set(image, state);
        return overlay;
      }

      function position(image, overlay) {
        const rect = image.getBoundingClientRect();
        overlay.style.left = `${rect.left + window.scrollX}px`;
        overlay.style.top = `${rect.top + window.scrollY}px`;
        overlay.style.width = `${rect.width}px`;
        overlay.style.height = `${rect.height}px`;
        overlay.style.display = rect.width > 0 && rect.height > 0 ? 'block' : 'none';
      }

      function scan() {
        for (const image of Array.from(document.images)) {
          if (!isCandidate(image)) continue;
          const state = states.get(image);
          if (state && (state.status === 'loading' || state.status === 'done')) {
            position(image, state.overlay);
            continue;
          }

          const overlay = ensureOverlay(image);
          position(image, overlay);
          overlay.innerHTML = '<div style="display:grid;place-items:center;width:100%;height:44px;border-radius:8px;background:rgba(255,255,255,.92);font:700 13px -apple-system;color:#111">Traduction...</div>';
          states.set(image, { status: 'loading', overlay });

          window.webkit.messageHandlers.webtoonLensImage.postMessage({
            imageID: stableId(image),
            imageURL: imageURL(image),
            pageURL: location.href
          });
        }
      }

      function renderBubble(segment, overlay) {
        const box = segment.boundingBox;
        if (!box) return;
        const bubble = document.createElement('div');
        bubble.textContent = segment.translatedText || '';
        bubble.style.position = 'absolute';
        bubble.style.left = `${box.x * 100}%`;
        bubble.style.top = `${box.y * 100}%`;
        bubble.style.width = `${Math.max(14, box.width * 100)}%`;
        bubble.style.minHeight = `${Math.max(32, box.height * overlay.clientHeight)}px`;
        bubble.style.display = 'grid';
        bubble.style.placeItems = 'center';
        bubble.style.padding = '4px 6px';
        bubble.style.border = '1px solid rgba(0,0,0,.28)';
        bubble.style.borderRadius = '8px';
        bubble.style.background = 'rgba(255,255,255,.95)';
        bubble.style.color = '#111';
        bubble.style.font = '800 12px -apple-system, BlinkMacSystemFont, sans-serif';
        bubble.style.lineHeight = '1.12';
        bubble.style.textAlign = 'center';
        bubble.style.boxShadow = '0 6px 16px rgba(0,0,0,.16)';
        overlay.appendChild(bubble);
      }

      function findImage(imageID) {
        return Array.from(document.images).find((image) => image.dataset.webtoonLensId === imageID);
      }

      window.WebtoonLensNative = {
        setAutoTranslate(enabled) {
          autoTranslate = Boolean(enabled);
          if (autoTranslate) scheduleScan();
        },
        renderTranslation(payload) {
          const image = findImage(payload.imageID);
          if (!image) return;
          const overlay = ensureOverlay(image);
          position(image, overlay);
          overlay.innerHTML = '';
          for (const segment of payload.result.segments || []) {
            renderBubble(segment, overlay);
          }
          states.set(image, { status: 'done', overlay });
        },
        markFailed(imageID, message) {
          const image = findImage(imageID);
          if (!image) return;
          const overlay = ensureOverlay(image);
          position(image, overlay);
          overlay.innerHTML = `<div style="display:grid;place-items:center;width:100%;min-height:44px;border-radius:8px;background:rgba(255,245,245,.95);font:700 12px -apple-system;color:#8a1111">${message}</div>`;
          states.set(image, { status: 'failed', overlay });
        },
        scan
      };

      function scheduleScan() {
        if (!autoTranslate) return;
        clearTimeout(timer);
        timer = setTimeout(scan, 220);
      }

      window.addEventListener('scroll', () => {
        for (const image of Array.from(document.images)) {
          const state = states.get(image);
          if (state && state.overlay) position(image, state.overlay);
        }
        scheduleScan();
      }, { passive: true });

      window.addEventListener('resize', scheduleScan, { passive: true });
      new MutationObserver(scheduleScan).observe(document.documentElement, { childList: true, subtree: true });
      document.addEventListener('visibilitychange', scheduleScan);
      scheduleScan();
    })();
    """
}
