import SwiftUI

struct CleanView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                Section {
                    AnalysisBanner()
                }
                Section {
                    ForEach(store.insights.cleanup) { group in
                        NavigationLink(value: group.kind) {
                            HStack(spacing: 14) {
                                Image(systemName: group.kind.systemImage)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 34, height: 34)
                                    .background(color(for: group.kind).gradient,
                                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.kind.title)
                                    Text(group.kind.subtitle)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(group.ids.count)")
                                        .font(.headline)
                                    Text(group.bytes.formattedBytes)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(group.ids.isEmpty)
                    }
                } footer: {
                    Text("Les photos favorites ne sont jamais proposées.")
                }
            }
            .navigationTitle("Nettoyer")
            .navigationDestination(for: CleanupKind.self) { kind in
                CleanupDetailView(kind: kind)
            }
        }
    }

    private func color(for kind: CleanupKind) -> Color {
        switch kind {
        case .screenshots: return .blue
        case .blurry: return .gray
        case .bursts: return .purple
        case .documents: return .orange
        case .largeVideos: return .red
        }
    }
}

struct CleanupDetailView: View {
    @Environment(AppStore.self) private var store
    let kind: CleanupKind
    @State private var selection = Set<String>()

    private var ids: [String] {
        store.insights.cleanup.first { $0.kind == kind }?.ids ?? []
    }

    var body: some View {
        Group {
            if ids.isEmpty {
                EmptyStateView(title: "C'est propre !", systemImage: "sparkles", message: "Plus rien dans cette catégorie.")
            } else {
                SelectableGrid(
                    ids: ids,
                    selection: $selection,
                    header: "\(kind.subtitle) Touchez les photos à supprimer, ou « Tout » pour tout sélectionner."
                ) { id in
                    if kind == .largeVideos, let info = store.photo(id) {
                        Text(info.fileSize.formattedBytes)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.55), in: Capsule())
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    ActionBar(
                        deleteTitle: "Supprimer (\(selection.count)) · \(store.bytes(of: selection).formattedBytes)",
                        deleteEnabled: !selection.isEmpty,
                        onDelete: {
                            Task {
                                let chosen = Array(selection)
                                if await store.delete(chosen, source: .cleanup) {
                                    selection.subtract(chosen)
                                }
                            }
                        },
                        secondaryTitle: kind == .largeVideos ? nil : "Garder",
                        onSecondary: kind == .largeVideos ? nil : {
                            store.record(.keep, ids: Array(selection), source: .cleanup)
                            selection.removeAll()
                        }
                    )
                }
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(selection.count == ids.count && !ids.isEmpty ? "Aucune" : "Tout") {
                    if selection.count == ids.count {
                        selection.removeAll()
                    } else {
                        selection = Set(ids)
                    }
                }
                .disabled(ids.isEmpty)
            }
        }
        .onChange(of: ids) { _, newIDs in
            selection.formIntersection(newIDs)
        }
    }
}
