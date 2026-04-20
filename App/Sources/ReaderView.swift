import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import WebtoonLensCore

struct ReaderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppModel.self) private var appModel
    @Query(sort: \SeriesProfile.updatedAt, order: .reverse) private var profiles: [SeriesProfile]
    @Query(sort: \TermMemoryEntry.updatedAt, order: .reverse) private var terms: [TermMemoryEntry]
    @Query(sort: \TranslationJob.createdAt, order: .reverse) private var jobs: [TranslationJob]

    @State private var selectedSeriesID = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var selectedImageData: Data?
    @State private var result: TranslationResult?
    @State private var isTranslating = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Label("Choisir une image", systemImage: "photo")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        Task { await translateSelectedImage() }
                    } label: {
                        if isTranslating {
                            ProgressView()
                        } else {
                            Label("Traduire", systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedImage == nil || isTranslating)
                }

                if !profiles.isEmpty {
                    Picker("Serie", selection: $selectedSeriesID) {
                        Text("Aucune").tag("")
                        ForEach(profiles) { profile in
                            Text(profile.title).tag(profile.id)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding()
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }

                if let selectedImage {
                    TranslatedImageView(image: selectedImage, result: result)
                } else {
                    ContentUnavailableView(
                        "Aucune image",
                        systemImage: "photo.badge.plus",
                        description: Text("Importe une capture, ou lance le raccourci Traduire ce webtoon depuis une autre app.")
                    )
                    .frame(minHeight: 280)
                }

                if let result {
                    ResultSummary(result: result)
                }

                HistoryList(jobs: Array(jobs.prefix(8)))
            }
            .padding()
        }
        .task(id: appModel.handoffRefreshToken) {
            await loadPendingHandoffImage()
        }
        .onAppear {
            if selectedSeriesID.isEmpty, let first = profiles.first {
                selectedSeriesID = first.id
            }
        }
        .onChange(of: selectedItem) { _, newValue in
            Task { await loadPhotoPickerItem(newValue) }
        }
    }

    private func loadPhotoPickerItem(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                errorMessage = "Impossible de lire cette image."
                return
            }
            selectedImageData = data
            selectedImage = image
            result = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadPendingHandoffImage() async {
        do {
            guard let pending = try SharedHandoffStore.consumePendingImage() else { return }
            let data = try Data(contentsOf: pending.url)
            guard let image = UIImage(data: data) else {
                errorMessage = "La capture recue par Raccourcis n'est pas lisible."
                return
            }
            selectedImageData = data
            selectedImage = image
            result = nil
            errorMessage = nil
            await translateSelectedImage()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func translateSelectedImage() async {
        guard let selectedImage else { return }
        isTranslating = true
        errorMessage = nil
        defer { isTranslating = false }

        do {
            let settings = SharedSettingsStore.shared
            let client: TranslationClientProtocol = if let backendURL = settings.backendBaseURL {
                WebtoonTranslationClient(baseURL: backendURL)
            } else {
                LocalPreviewTranslationClient()
            }
            let activeProfile = profiles.first { $0.id == selectedSeriesID }
            let activeTerms = selectedSeriesID.isEmpty ? terms : terms.filter { $0.seriesID == selectedSeriesID }

            let pipeline = WebtoonTranslationPipeline(client: client)
            let translated = try await pipeline.translate(
                image: selectedImage,
                imageData: selectedImageData,
                seriesID: activeProfile?.id,
                sourceLanguage: activeProfile?.sourceLanguage ?? WebtoonLensConstants.autoSourceLanguage,
                targetLanguage: activeProfile?.targetLanguage ?? WebtoonLensConstants.defaultTargetLanguage,
                glossary: GlossaryResolver.instructions(from: activeTerms),
                style: activeProfile?.stylePrompt ?? settings.defaultStylePrompt
            )
            result = translated
            persist(translated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persist(_ result: TranslationResult) {
        let job = TranslationJob(
            seriesID: selectedSeriesID.isEmpty ? nil : selectedSeriesID,
            imageHash: result.imageHash,
            sourceLanguage: result.detectedSourceLanguage ?? WebtoonLensConstants.autoSourceLanguage,
            targetLanguage: result.targetLanguage,
            status: "completed",
            durationMilliseconds: result.durationMilliseconds
        )
        modelContext.insert(job)
        for payload in result.segments {
            modelContext.insert(TranslatedSegment(jobID: job.id, payload: payload))
        }
        try? modelContext.save()
    }
}

private struct TranslatedImageView: View {
    let image: UIImage
    let result: TranslationResult?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()

            if let result {
                GeometryReader { proxy in
                    ForEach(result.segments) { segment in
                        let box = segment.boundingBox
                        let width = max(84, proxy.size.width * box.width)
                        let height = max(34, proxy.size.height * box.height)
                        Text(segment.translatedText)
                            .font(.caption2.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.65)
                            .lineLimit(5)
                            .padding(4)
                            .frame(width: width, height: height)
                            .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.black.opacity(0.25), lineWidth: 1)
                            )
                            .position(
                                x: proxy.size.width * box.midX,
                                y: proxy.size.height * box.midY
                            )
                    }
                }
            }
        }
        .aspectRatio(image.size.width / max(1, image.size.height), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.secondary.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct ResultSummary: View {
    let result: TranslationResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Resultat")
                .font(.headline)
            Text("\(result.segments.count) bulles traduites en \(result.durationMilliseconds) ms")
                .foregroundStyle(.secondary)
            if !result.glossaryUpdates.isEmpty {
                Text("\(result.glossaryUpdates.count) termes proposes pour le glossaire")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct HistoryList: View {
    let jobs: [TranslationJob]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Historique recent")
                .font(.headline)

            if jobs.isEmpty {
                Text("Les traductions terminees apparaitront ici.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(jobs) { job in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(String(job.imageHash.prefix(12)))
                                .font(.subheadline.monospaced())
                            Text(job.createdAt, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(job.durationMilliseconds) ms")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}
