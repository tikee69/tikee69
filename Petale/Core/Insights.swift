import Foundation

/// Tout ce que l'app déduit de la photothèque (calculé en arrière-plan).
struct Insights: Sendable {
    var series: [PhotoSeries] = []
    var cleanup: [CleanupGroup] = []
    var suggestions: [Suggestion] = []
    var learning: LearningStatus = .empty
    var albums: [AlbumProposal] = []
    /// Espace récupérable (sans compter deux fois une même photo).
    var reclaimableBytes: Int64 = 0
    var suggestionByID: [String: Suggestion] = [:]

    static let empty = Insights()

    var seriesReclaimableCount: Int {
        series.reduce(0) { $0 + $1.photoIDs.count - $1.keepIDs.count }
    }

    static func compute(state: PersistedState) -> Insights {
        let photos = Array(state.photos.values)
        var vectors: [String: [Float]] = [:]
        vectors.reserveCapacity(photos.count)
        for p in photos {
            if let a = p.analysis {
                let v = a.vector
                if !v.isEmpty { vectors[p.id] = v }
            }
        }

        let basket = Set(state.basket)
        var insights = Insights()

        // Séries : on masque celles dont toutes les photos ont déjà été « gardées ».
        insights.series = SeriesFinder.find(
            photos: photos.filter { !basket.contains($0.id) },
            vectors: vectors,
            similarity: state.settings.seriesSimilarity,
            maxGap: state.settings.seriesMaxGap
        )
        .filter { s in !s.photoIDs.allSatisfy { state.decisions[$0]?.kind == .keep } }
        .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }

        insights.cleanup = CleanupFinder.groups(
            photos: photos.filter { !basket.contains($0.id) && state.decisions[$0.id]?.kind != .keep },
            settings: state.settings
        )

        insights.learning = SuggestionEngine.status(decisions: state.decisions, settings: state.settings)
        insights.suggestions = SuggestionEngine.suggest(
            photos: photos,
            vectors: vectors,
            decisions: state.decisions,
            excluded: basket,
            settings: state.settings
        )
        insights.suggestionByID = Dictionary(uniqueKeysWithValues: insights.suggestions.map { ($0.id, $0) })

        insights.albums = AlbumSuggester.proposals(photos: photos, dismissed: Set(state.dismissedAlbums))

        // Espace récupérable total
        var reclaimable = Set<String>()
        for s in insights.series { reclaimable.formUnion(s.photoIDs.filter { !s.keepIDs.contains($0) }) }
        for g in insights.cleanup where g.kind != .largeVideos { reclaimable.formUnion(g.ids) }
        for s in insights.suggestions { reclaimable.insert(s.id) }
        reclaimable.formUnion(basket)
        insights.reclaimableBytes = reclaimable.reduce(Int64(0)) { $0 + (state.photos[$1]?.fileSize ?? 0) }

        return insights
    }
}

extension Int64 {
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension Double {
    var percentString: String { "\(Int((self * 100).rounded())) %" }
}
