import SwiftData
import SwiftUI
import WebtoonLensCore

struct SeriesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SeriesProfile.updatedAt, order: .reverse) private var profiles: [SeriesProfile]
    @Query(sort: \TermMemoryEntry.updatedAt, order: .reverse) private var terms: [TermMemoryEntry]

    @State private var selectedSeriesID = ""
    @State private var newSeriesTitle = ""
    @State private var newSource = ""
    @State private var newTranslation = ""
    @State private var newCategory: TermCategory = .unknown
    @State private var newTermLocked = true

    var body: some View {
        Form {
            Section("Serie") {
                if profiles.isEmpty {
                    Text("Cree une serie pour stabiliser les noms, pouvoirs et lieux.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Serie active", selection: $selectedSeriesID) {
                        ForEach(profiles) { profile in
                            Text(profile.title).tag(profile.id)
                        }
                    }
                }

                HStack {
                    TextField("Nom de la serie", text: $newSeriesTitle)
                    Button("Ajouter") {
                        addSeries()
                    }
                    .disabled(newSeriesTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section("Nouveau terme") {
                TextField("Terme source", text: $newSource)
                TextField("Traduction stable", text: $newTranslation)
                Picker("Categorie", selection: $newCategory) {
                    ForEach(TermCategory.allCases, id: \.self) { category in
                        Text(category.rawValue.capitalized).tag(category)
                    }
                }
                Toggle("Verrouiller", isOn: $newTermLocked)
                Button("Ajouter au glossaire") {
                    addTerm()
                }
                .disabled(selectedSeriesID.isEmpty || newSource.isEmpty || newTranslation.isEmpty)
            }

            Section("Glossaire") {
                let visibleTerms = terms.filter { $0.seriesID == selectedSeriesID }
                if visibleTerms.isEmpty {
                    Text("Aucun terme pour cette serie.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleTerms) { term in
                        TermRow(term: term)
                    }
                    .onDelete { offsets in
                        deleteTerms(at: offsets, from: visibleTerms)
                    }
                }
            }
        }
        .onAppear {
            if selectedSeriesID.isEmpty, let first = profiles.first {
                selectedSeriesID = first.id
            }
        }
        .onChange(of: profiles.map(\.id)) { _, ids in
            if selectedSeriesID.isEmpty || !ids.contains(selectedSeriesID) {
                selectedSeriesID = ids.first ?? ""
            }
        }
        .onDisappear {
            try? modelContext.save()
            try? SharedGlossarySnapshotStore.save(terms: terms)
        }
    }

    private func addSeries() {
        let title = newSeriesTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let profile = SeriesProfile(title: title)
        modelContext.insert(profile)
        selectedSeriesID = profile.id
        newSeriesTitle = ""
        try? modelContext.save()
        try? SharedGlossarySnapshotStore.save(terms: terms)
    }

    private func addTerm() {
        let source = newSource.trimmingCharacters(in: .whitespacesAndNewlines)
        let translation = newTranslation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedSeriesID.isEmpty, !source.isEmpty, !translation.isEmpty else { return }

        let entry = TermMemoryEntry(
            seriesID: selectedSeriesID,
            source: source,
            translation: translation,
            category: newCategory,
            isLocked: newTermLocked,
            confidence: 1
        )
        modelContext.insert(entry)
        newSource = ""
        newTranslation = ""
        newCategory = .unknown
        try? modelContext.save()
        try? SharedGlossarySnapshotStore.save(terms: terms + [entry])
    }

    private func deleteTerms(at offsets: IndexSet, from visibleTerms: [TermMemoryEntry]) {
        let deletedIDs = Set(offsets.map { visibleTerms[$0].id })
        for offset in offsets {
            modelContext.delete(visibleTerms[offset])
        }
        try? modelContext.save()
        try? SharedGlossarySnapshotStore.save(terms: terms.filter { !deletedIDs.contains($0.id) })
    }
}

private struct TermRow: View {
    @Bindable var term: TermMemoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(term.source)
                    .font(.headline)
                Spacer()
                if term.isLocked {
                    Label("Verrouille", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            TextField("Traduction", text: $term.translation)
            Toggle("Toujours garder cette traduction", isOn: $term.isLocked)
                .font(.caption)
        }
    }
}
