import SwiftData
import SwiftUI
import WebtoonLensCore

struct ReadingHistoryView: View {
    @Environment(AppModel.self) private var appModel
    @Query(sort: \TranslationJob.createdAt, order: .reverse) private var jobs: [TranslationJob]

    private var readings: [TranslationJob] { jobs.filter { $0.sourceURL != nil } }

    var body: some View {
        List {
            if readings.isEmpty {
                ContentUnavailableView(
                    "Pas encore de lecture",
                    systemImage: "clock",
                    description: Text("Tes chapitres traduits apparaitront ici. Choisir une lecture remet son lien dans Lecture, sans lancer de traduction.")
                )
                .accessibilityIdentifier("v2.historyEmpty")
            } else {
                ForEach(readings) { reading in
                    Button {
                        guard let value = reading.sourceURL, let url = try? BrowserAddress.parse(value) else { return }
                        appModel.pendingHistoryURL = url
                        appModel.readingChromeCollapsed = false
                        appModel.selectedTab = .webtoon
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(reading.sourceTitle ?? "Lecture").font(.headline).foregroundStyle(.primary)
                            Text(URL(string: reading.sourceURL ?? "")?.host ?? "")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Text(reading.createdAt, format: .dateTime.day().month().hour().minute())
                                Spacer()
                                Text(reading.status == "partial" ? "Traduction partielle" : "Traduction disponible")
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .accessibilityIdentifier("v2.historyEntry.\(reading.id)")
                }
            }
        }
        .navigationTitle("Historique")
        .accessibilityIdentifier("v2.history")
    }
}
