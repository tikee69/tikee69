import SwiftUI

/// Tri façon Tinder : gauche = supprimer, droite = garder, haut = favori.
struct SwipeView: View {
    @Environment(AppStore.self) private var store
    @State private var queue: [String] = []
    @State private var offset: CGSize = .zero
    @State private var history: [SwipeAction] = []
    @State private var isAnimatingOut = false
    @State private var showBasket = false

    enum SwipeKind { case delete, keep, favorite }

    struct SwipeAction {
        let id: String
        let kind: SwipeKind
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if queue.isEmpty {
                    Spacer()
                    if store.isScanning {
                        ProgressView("Chargement…")
                    } else {
                        EmptyStateView(
                            title: "Tout est trié",
                            systemImage: "checkmark.seal.fill",
                            message: "Vous avez vu toutes vos photos. Revenez quand vous en aurez de nouvelles !"
                        )
                    }
                    Spacer()
                } else {
                    cards
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    buttons
                        .padding(.bottom, 12)
                }
            }
            .navigationTitle("Trier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(history.isEmpty || isAnimatingOut)
                    .accessibilityLabel("Annuler")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showBasket = true
                    } label: {
                        Label("\(store.basket.count)", systemImage: "trash")
                            .labelStyle(.titleAndIcon)
                    }
                    .disabled(store.basket.isEmpty)
                    .accessibilityLabel("Photos à supprimer")
                }
            }
            .sheet(isPresented: $showBasket) {
                BasketView()
            }
            .onAppear { refill() }
            .onChange(of: store.state.photos.count) { _, _ in refill() }
            .sensoryFeedback(.impact(weight: .light), trigger: history.count)
        }
    }

    // MARK: Cartes

    private var cards: some View {
        ZStack {
            if queue.count > 1 {
                SwipeCard(id: queue[1], offset: .zero)
                    .scaleEffect(0.94)
                    .offset(y: 14)
                    .opacity(0.8)
                    .allowsHitTesting(false)
            }
            if let top = queue.first {
                SwipeCard(id: top, offset: offset)
                    .id(top)
                    .offset(offset)
                    .rotationEffect(.degrees(Double(offset.width) / 22), anchor: .bottom)
                    .gesture(drag)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isAnimatingOut else { return }
                offset = value.translation
            }
            .onEnded { value in
                guard !isAnimatingOut else { return }
                let x = value.translation.width
                let predicted = value.predictedEndTranslation.width
                let y = value.translation.height
                if x > 110 || predicted > 320 {
                    swipe(.keep)
                } else if x < -110 || predicted < -320 {
                    swipe(.delete)
                } else if y < -160 && abs(x) < 80 {
                    swipe(.favorite)
                } else {
                    withAnimation(.spring(duration: 0.3)) { offset = .zero }
                }
            }
    }

    private var buttons: some View {
        HStack(spacing: 28) {
            RoundButton(systemImage: "xmark", color: .red, size: 64) { swipe(.delete) }
                .accessibilityLabel("Supprimer")
            RoundButton(systemImage: "heart.fill", color: .pink, size: 50) { swipe(.favorite) }
                .accessibilityLabel("Favori")
            RoundButton(systemImage: "checkmark", color: .green, size: 64) { swipe(.keep) }
                .accessibilityLabel("Garder")
        }
        .disabled(queue.isEmpty || isAnimatingOut)
    }

    // MARK: Actions

    private func swipe(_ kind: SwipeKind) {
        guard let id = queue.first, !isAnimatingOut else { return }
        isAnimatingOut = true
        let target: CGSize
        switch kind {
        case .delete: target = CGSize(width: -700, height: offset.height + 40)
        case .keep: target = CGSize(width: 700, height: offset.height + 40)
        case .favorite: target = CGSize(width: 0, height: -1000)
        }
        withAnimation(.easeIn(duration: 0.22)) { offset = target }

        Task {
            try? await Task.sleep(for: .milliseconds(230))
            switch kind {
            case .delete:
                store.addToBasket(id)
            case .keep:
                store.record(.keep, ids: [id], source: .swipe)
            case .favorite:
                if store.photo(id)?.isFavorite == true {
                    store.record(.keep, ids: [id], source: .favorite)
                } else {
                    await store.toggleFavorite(id)
                }
            }
            history.append(SwipeAction(id: id, kind: kind))
            if history.count > 50 { history.removeFirst() }
            if queue.first == id { queue.removeFirst() }
            offset = .zero
            isAnimatingOut = false
            if queue.count < 5 { refill() }
        }
    }

    private func undo() {
        guard let last = history.popLast() else { return }
        switch last.kind {
        case .delete: store.removeFromBasket([last.id])
        case .keep, .favorite: store.clearDecision(last.id)
        }
        queue.removeAll { $0 == last.id }
        queue.insert(last.id, at: 0)
    }

    private func refill() {
        queue.removeAll { store.photo($0) == nil }
        let more = store.swipeCandidates(excluding: Set(queue), limit: max(0, 30 - queue.count))
        queue.append(contentsOf: more)
    }
}

struct SwipeCard: View {
    @Environment(AppStore.self) private var store
    let id: String
    let offset: CGSize

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                AssetImage(id: id, pixelSize: CGSize(width: 1400, height: 1400), contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)

                info
                    .padding(18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(alignment: .topLeading) {
                Stamp(text: "GARDER", color: .green)
                    .rotationEffect(.degrees(-14))
                    .padding(28)
                    .opacity(Double(max(0, min(1, offset.width / 110))))
            }
            .overlay(alignment: .topTrailing) {
                Stamp(text: "SUPPRIMER", color: .red)
                    .rotationEffect(.degrees(14))
                    .padding(28)
                    .opacity(Double(max(0, min(1, -offset.width / 110))))
            }
            .overlay(alignment: .center) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 90))
                    .foregroundStyle(.pink)
                    .shadow(radius: 10)
                    .opacity(Double(max(0, min(1, -offset.height / 160))) * (abs(offset.width) < 80 ? 1 : 0))
            }
            .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
        }
    }

    @ViewBuilder
    private var info: some View {
        if let photo = store.photo(id) {
            VStack(alignment: .leading, spacing: 6) {
                if let suggestion = store.insights.suggestionByID[id] {
                    Label("L'IA pense que vous la supprimeriez (\(suggestion.confidence.percentString))", systemImage: "wand.and.stars")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                HStack(alignment: .lastTextBaseline) {
                    if let date = photo.creationDate {
                        Text(date.formatted(date: .long, time: .omitted))
                            .font(.title3.weight(.bold))
                    }
                    Spacer()
                    if photo.isVideo {
                        Label(formatDuration(photo.duration), systemImage: "video.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                Text(photo.fileSize.formattedBytes)
                    .font(.subheadline)
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct Stamp: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 30, weight: .heavy, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 4))
            .background(.ultraThinMaterial.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct RoundButton: View {
    let systemImage: String
    let color: Color
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .background(Color(.systemBackground), in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }
}

/// Photos glissées à gauche, en attente de suppression.
struct BasketView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selection = Set<String>()
    @State private var didInit = false

    var body: some View {
        NavigationStack {
            Group {
                if store.basket.isEmpty {
                    EmptyStateView(title: "Corbeille vide", systemImage: "trash", message: "Les photos glissées à gauche apparaîtront ici.")
                } else {
                    SelectableGrid(
                        ids: store.basket,
                        selection: $selection,
                        header: "Touchez une photo pour la désélectionner. Les photos supprimées restent 30 jours dans « Supprimés récemment »."
                    )
                    .safeAreaInset(edge: .bottom) {
                        ActionBar(
                            deleteTitle: "Supprimer (\(selection.count)) · \(store.bytes(of: selection).formattedBytes)",
                            deleteEnabled: !selection.isEmpty,
                            onDelete: {
                                Task {
                                    let ids = Array(selection)
                                    if await store.delete(ids, source: .swipe) {
                                        selection.subtract(ids)
                                        if store.basket.isEmpty { dismiss() }
                                    }
                                }
                            },
                            secondaryTitle: "Remettre",
                            onSecondary: {
                                store.removeFromBasket(Array(selection))
                                selection.removeAll()
                            }
                        )
                    }
                }
            }
            .navigationTitle("À supprimer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(selection.count == store.basket.count ? "Aucune" : "Toutes") {
                        if selection.count == store.basket.count {
                            selection.removeAll()
                        } else {
                            selection = Set(store.basket)
                        }
                    }
                    .disabled(store.basket.isEmpty)
                }
            }
            .onAppear {
                if !didInit {
                    selection = Set(store.basket)
                    didInit = true
                }
            }
        }
    }
}
