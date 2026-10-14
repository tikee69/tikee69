import Photos
import SwiftUI

/// Affiche une photo de la photothèque (vignette ou grand format).
struct AssetImage: View {
    let id: String
    var pixelSize: CGSize = CGSize(width: 300, height: 300)
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(Color(.secondarySystemFill))
            }
        }
        .task(id: id) {
            let mode: PHImageContentMode = contentMode == .fill ? .aspectFill : .aspectFit
            for await loaded in ImageLoader.images(for: id, pixelSize: pixelSize, contentMode: mode) {
                image = loaded
            }
        }
    }
}

/// Vignette carrée façon app Photos (avec durée pour les vidéos).
struct ThumbnailView: View {
    @Environment(AppStore.self) private var store
    let id: String
    var size: CGFloat = 300

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                AssetImage(id: id, pixelSize: CGSize(width: size, height: size))
            }
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if let info = store.photo(id), info.isVideo {
                    Text(formatDuration(info.duration))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(4)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if store.photo(id)?.isFavorite == true {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(4)
                }
            }
    }
}

func formatDuration(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
}

/// Aperçu en grand (appui long sur une vignette).
struct PhotoPreview: View {
    @Environment(AppStore.self) private var store
    let id: String

    var body: some View {
        VStack(spacing: 0) {
            AssetImage(id: id, pixelSize: CGSize(width: 1200, height: 1200), contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let info = store.photo(id) {
                PhotoCaption(info: info)
                    .padding(10)
            }
        }
        .frame(width: 340, height: 460)
        .background(Color(.systemBackground))
    }
}

struct PhotoCaption: View {
    let info: PhotoInfo

    var body: some View {
        HStack {
            if let date = info.creationDate {
                Text(date.formatted(date: .abbreviated, time: .shortened))
            }
            Spacer()
            Text(info.fileSize.formattedBytes)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

/// Grille de photos sélectionnables, avec barre d'actions en bas.
struct SelectableGrid<Badge: View>: View {
    @Environment(AppStore.self) private var store
    let ids: [String]
    @Binding var selection: Set<String>
    var header: String?
    @ViewBuilder var badge: (String) -> Badge

    private var columns: [GridItem] { [GridItem(.adaptive(minimum: 100, maximum: 160), spacing: 2)] }

    var body: some View {
        ScrollView {
            if let header {
                Text(header)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(ids, id: \.self) { id in
                    let isSelected = selection.contains(id)
                    ThumbnailView(id: id)
                        .overlay {
                            if isSelected { Color.black.opacity(0.25) }
                        }
                        .overlay(alignment: .topLeading) { badge(id).padding(4) }
                        .overlay(alignment: .bottomTrailing) {
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, Color.accentColor)
                                    .font(.title3)
                                    .padding(5)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isSelected { selection.remove(id) } else { selection.insert(id) }
                        }
                        .contextMenu {
                            Button {
                                if isSelected { selection.remove(id) } else { selection.insert(id) }
                            } label: {
                                Label(isSelected ? "Désélectionner" : "Sélectionner",
                                      systemImage: isSelected ? "circle" : "checkmark.circle")
                            }
                        } preview: {
                            PhotoPreview(id: id).environment(store)
                        }
                }
            }
            .padding(.bottom, 100)
        }
    }
}

extension SelectableGrid where Badge == EmptyView {
    init(ids: [String], selection: Binding<Set<String>>, header: String? = nil) {
        self.ids = ids
        self._selection = selection
        self.header = header
        self.badge = { _ in EmptyView() }
    }
}

/// Barre d'actions flottante en bas de l'écran.
struct ActionBar: View {
    var deleteTitle: String
    var deleteEnabled: Bool
    var onDelete: () -> Void
    var secondaryTitle: String?
    var onSecondary: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            if let secondaryTitle, let onSecondary {
                Button(action: onSecondary) {
                    Text(secondaryTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            Button(role: .destructive, action: onDelete) {
                Label(deleteTitle, systemImage: "trash")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(!deleteEnabled)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

/// Bloc « rien à afficher » avec icône.
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
    }
}

/// Bandeau de progression de l'analyse.
struct AnalysisBanner: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if store.isAnalyzing {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "sparkle.magnifyingglass")
                    Text("Analyse des photos… \(store.analysisDone)/\(store.analysisTotal)")
                        .font(.subheadline.weight(.medium))
                }
                ProgressView(value: Double(store.analysisDone), total: Double(max(store.analysisTotal, 1)))
                Text("Gardez l'app ouverte pour aller plus vite. Les résultats s'affinent au fur et à mesure.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if store.isScanning {
            HStack {
                ProgressView()
                Text("Lecture de la photothèque…").font(.subheadline)
            }
        }
    }
}
