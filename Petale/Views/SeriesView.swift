import SwiftUI

/// Séries de photos presque identiques : l'app propose de garder la ou les plus belles.
struct SeriesListView: View {
    @Environment(AppStore.self) private var store
    /// Choix modifiés à la main, par série.
    @State private var overrides: [String: Set<String>] = [:]
    @State private var confirmAll = false
    @State private var working = false

    var body: some View {
        NavigationStack {
            Group {
                if store.insights.series.isEmpty {
                    if store.isAnalyzing || store.isComputing {
                        VStack(spacing: 16) {
                            ProgressView()
                            Text("Recherche des séries…").foregroundStyle(.secondary)
                            AnalysisBanner().padding(.horizontal)
                        }
                    } else {
                        EmptyStateView(
                            title: "Aucune série",
                            systemImage: "square.stack.3d.down.right",
                            message: "Quand vous prenez plusieurs photos presque identiques, elles apparaîtront ici."
                        )
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pour chaque série, Pétale garde la plus belle photo (nette, bien exposée, visages réussis). Touchez une photo pour changer.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(store.insights.series.count) séries · \(totalToDelete) photos en trop · \(totalBytes.formattedBytes)")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.top, 4)

                        LazyVStack(spacing: 16) {
                            ForEach(store.insights.series) { series in
                                SeriesCard(
                                    series: series,
                                    keep: keepBinding(for: series),
                                    onApply: { apply([series]) },
                                    onIgnore: { store.record(.keep, ids: series.photoIDs, source: .series) }
                                )
                            }
                        }
                        .padding()
                        .padding(.bottom, 80)
                    }
                    .background(Color(.systemGroupedBackground))
                    .safeAreaInset(edge: .bottom) {
                        ActionBar(
                            deleteTitle: "Tout appliquer (\(totalToDelete))",
                            deleteEnabled: totalToDelete > 0 && !working,
                            onDelete: { confirmAll = true }
                        )
                    }
                }
            }
            .navigationTitle("Séries")
            .confirmationDialog(
                "Garder les meilleures photos de toutes les séries et supprimer les \(totalToDelete) autres ?",
                isPresented: $confirmAll,
                titleVisibility: .visible
            ) {
                Button("Supprimer \(totalToDelete) photos", role: .destructive) {
                    apply(store.insights.series)
                }
            } message: {
                Text("Elles resteront 30 jours dans « Supprimés récemment ».")
            }
        }
    }

    private func keepSet(_ series: PhotoSeries) -> Set<String> {
        overrides[series.id] ?? series.keepIDs
    }

    private func keepBinding(for series: PhotoSeries) -> Binding<Set<String>> {
        Binding(
            get: { keepSet(series) },
            set: { overrides[series.id] = $0 }
        )
    }

    private var totalToDelete: Int {
        store.insights.series.reduce(0) { total, s in
            let keep = keepSet(s)
            return total + s.photoIDs.filter { !keep.contains($0) }.count
        }
    }

    private var totalBytes: Int64 {
        store.insights.series.reduce(Int64(0)) { total, s in
            let keep = keepSet(s)
            return total + store.bytes(of: s.photoIDs.filter { !keep.contains($0) })
        }
    }

    private func apply(_ list: [PhotoSeries]) {
        var toDelete: [String] = []
        var toKeep: [String] = []
        for s in list {
            let keep = keepSet(s)
            toDelete += s.photoIDs.filter { !keep.contains($0) }
            toKeep += s.photoIDs.filter { keep.contains($0) }
        }
        working = true
        Task {
            if await store.delete(toDelete, source: .series, alsoKeep: toKeep) {
                for s in list { overrides[s.id] = nil }
            }
            working = false
        }
    }
}

struct SeriesCard: View {
    @Environment(AppStore.self) private var store
    let series: PhotoSeries
    @Binding var keep: Set<String>
    let onApply: () -> Void
    let onIgnore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(series.photoIDs.count) photos similaires")
                        .font(.headline)
                    if let date = series.date {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Menu {
                    Button("Tout garder (ignorer la série)", systemImage: "checkmark.circle", action: onIgnore)
                    Button("Revenir au choix de Pétale", systemImage: "wand.and.stars") { keep = series.keepIDs }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(series.photoIDs, id: \.self) { id in
                        let kept = keep.contains(id)
                        ThumbnailView(id: id, size: 260)
                            .frame(width: 104, height: 104)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                if !kept {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(.black.opacity(0.45))
                                }
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(kept ? Color.green : .clear, lineWidth: 3)
                            }
                            .overlay(alignment: .topLeading) {
                                if id == series.bestID {
                                    Image(systemName: "star.fill")
                                        .font(.caption)
                                        .foregroundStyle(.yellow)
                                        .padding(5)
                                        .background(.black.opacity(0.4), in: Circle())
                                        .padding(4)
                                }
                            }
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: kept ? "checkmark.circle.fill" : "trash.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, kept ? Color.green : Color.red)
                                    .font(.title3)
                                    .padding(4)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if kept { keep.remove(id) } else { keep.insert(id) }
                            }
                            .contextMenu {
                                Button(kept ? "Supprimer celle-ci" : "Garder celle-ci",
                                       systemImage: kept ? "trash" : "checkmark") {
                                    if kept { keep.remove(id) } else { keep.insert(id) }
                                }
                            } preview: {
                                PhotoPreview(id: id).environment(store)
                            }
                    }
                }
            }

            if !series.bestReasons.isEmpty {
                Label(series.bestReasons.joined(separator: " · "), systemImage: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let toDelete = series.photoIDs.filter { !keep.contains($0) }
            Button(action: onApply) {
                Text(toDelete.isEmpty
                     ? "Tout garder"
                     : "Garder \(keep.count), supprimer \(toDelete.count) · \(store.bytes(of: toDelete).formattedBytes)")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(toDelete.isEmpty ? .green : .red)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
