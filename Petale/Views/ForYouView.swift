import SwiftUI

struct ForYouView: View {
    @Environment(AppStore.self) private var store
    @Binding var selection: AppTab
    @State private var segment = Segment.suggestions

    enum Segment: Hashable { case suggestions, albums }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Affichage", selection: $segment) {
                    Text("Suggestions").tag(Segment.suggestions)
                    Text("Albums").tag(Segment.albums)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                switch segment {
                case .suggestions: SuggestionsView(selectionTab: $selection)
                case .albums: AlbumProposalsView()
                }
            }
            .navigationTitle("Pour vous")
            .navigationDestination(for: String.self) { label in
                if let proposal = store.insights.albums.first(where: { $0.id == label }) {
                    AlbumProposalDetail(proposal: proposal)
                } else {
                    EmptyStateView(title: "Album créé", systemImage: "checkmark.circle", message: "Cette proposition a été traitée.")
                }
            }
        }
    }
}

// MARK: - Suggestions apprises

struct SuggestionsView: View {
    @Environment(AppStore.self) private var store
    @Binding var selectionTab: AppTab
    @State private var selection = Set<String>()

    private var ids: [String] { store.insights.suggestions.map(\.id) }

    var body: some View {
        let learning = store.insights.learning
        Group {
            if !learning.isReady {
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 60))
                        .foregroundStyle(Color.accentColor.gradient)
                    Text("L'IA apprend à vous connaître")
                        .font(.title2.bold())
                    Text("Triez encore \(learning.remaining) photos (dans « Trier », « Séries » ou « Nettoyer ») ou supprimez-en dans l'app Photos. Pétale vous proposera ensuite les photos qui ressemblent à celles dont vous vous débarrassez.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 30)
                    ProgressView(value: learning.progress)
                        .padding(.horizontal, 60)
                    Button("Commencer à trier") { selectionTab = .swipe }
                        .buttonStyle(.borderedProminent)
                    Spacer()
                }
            } else if ids.isEmpty {
                EmptyStateView(
                    title: "Aucune suggestion",
                    systemImage: "wand.and.stars",
                    message: "Pétale n'a trouvé aucune photo qui ressemble assez à celles que vous supprimez. Continuez à trier pour l'aider."
                )
            } else {
                SelectableGrid(
                    ids: ids,
                    selection: $selection,
                    header: "Ces photos ressemblent à celles que vous supprimez d'habitude. Le pourcentage indique la confiance de l'IA."
                ) { id in
                    if let s = store.insights.suggestionByID[id] {
                        Text(s.confidence.percentString)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.9), in: Capsule())
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    ActionBar(
                        deleteTitle: "Supprimer (\(selection.count))",
                        deleteEnabled: !selection.isEmpty,
                        onDelete: {
                            Task {
                                let chosen = Array(selection)
                                if await store.delete(chosen, source: .suggestion) {
                                    selection.subtract(chosen)
                                }
                            }
                        },
                        secondaryTitle: "Garder",
                        onSecondary: {
                            // Garder apprend aussi à l'IA qu'elle s'est trompée.
                            store.record(.keep, ids: Array(selection), source: .suggestion)
                            selection.removeAll()
                        }
                    )
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(selection.count == ids.count ? "Aucune" : "Tout") {
                            selection = selection.count == ids.count ? [] : Set(ids)
                        }
                    }
                }
            }
        }
        .onChange(of: ids) { _, newIDs in
            selection.formIntersection(newIDs)
        }
    }
}

// MARK: - Albums proposés

struct AlbumProposalsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if store.insights.albums.isEmpty {
            EmptyStateView(
                title: "Aucun album à proposer",
                systemImage: "rectangle.stack.badge.plus",
                message: store.isAnalyzing
                    ? "L'analyse est en cours, les propositions arriveront bientôt."
                    : "Pétale propose un album quand il trouve au moins \(AlbumSuggester.minimumPhotos) photos du même thème."
            )
        } else {
            List {
                Section {
                    ForEach(store.insights.albums) { album in
                        NavigationLink(value: album.id) {
                            HStack(spacing: 12) {
                                ThumbnailView(id: album.ids[0], size: 200)
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                VStack(alignment: .leading, spacing: 3) {
                                    Label(album.title, systemImage: album.symbol)
                                        .font(.headline)
                                    Text("\(album.ids.count) photos")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions {
                            Button("Ignorer", systemImage: "xmark") { store.dismissAlbum(album) }
                                .tint(.gray)
                        }
                    }
                } footer: {
                    Text("Albums proposés à partir de ce que l'IA reconnaît sur vos photos. Rien n'est créé sans votre accord.")
                }
            }
        }
    }
}

struct AlbumProposalDetail: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let proposal: AlbumProposal
    @State private var title = ""
    @State private var selection = Set<String>()
    @State private var didInit = false
    @State private var working = false

    var body: some View {
        VStack(spacing: 0) {
            TextField("Nom de l'album", text: $title)
                .font(.title3.weight(.semibold))
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.vertical, 8)
            SelectableGrid(
                ids: proposal.ids,
                selection: $selection,
                header: "Touchez une photo pour la retirer de l'album."
            )
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button {
                    store.dismissAlbum(proposal)
                    dismiss()
                } label: {
                    Text("Ignorer").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    working = true
                    Task {
                        let ok = await store.createAlbum(proposal, title: title, ids: Array(selection))
                        working = false
                        if ok { dismiss() }
                    }
                } label: {
                    Label("Créer (\(selection.count))", systemImage: "plus.rectangle.on.folder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selection.isEmpty || working)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .navigationTitle(proposal.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !didInit {
                title = proposal.title
                selection = Set(proposal.ids)
                didInit = true
            }
        }
    }
}
