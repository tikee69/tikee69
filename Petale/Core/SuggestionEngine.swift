import Foundation

struct Suggestion: Identifiable, Sendable {
    var id: String
    /// Probabilité estimée que vous vouliez supprimer cette photo (0…1).
    var confidence: Double
    /// Nombre de photos déjà triées qui lui ressemblent.
    var similarCount: Int
    /// Parmi elles, combien ont été supprimées.
    var deletedNeighbours: Int
}

struct LearningStatus: Sendable {
    var keeps: Int
    var deletes: Int
    var required: Int

    var total: Int { keeps + deletes }
    var isReady: Bool { total >= required && deletes >= 5 && keeps >= 5 }
    var remaining: Int { max(0, required - total, 5 - deletes, 5 - keeps) }
    var progress: Double { required > 0 ? min(1, Double(total) / Double(required)) : 1 }

    static let empty = LearningStatus(keeps: 0, deletes: 0, required: 30)
}

/// Apprend de vos choix : une photo est suggérée si les photos qui lui ressemblent
/// le plus ont presque toutes été supprimées (méthode des « plus proches voisins »).
enum SuggestionEngine {
    static let neighbourCount = 10
    static let minRelevance: Float = 0.70
    static let minNeighbours = 3

    static func status(decisions: [String: Decision], settings: AppSettings) -> LearningStatus {
        var keeps = 0, deletes = 0
        for d in decisions.values where d.vectorData != nil {
            if d.kind == .keep { keeps += 1 } else { deletes += 1 }
        }
        return LearningStatus(keeps: keeps, deletes: deletes, required: settings.minDecisionsForSuggestions)
    }

    static func suggest(
        photos: [PhotoInfo],
        vectors: [String: [Float]],
        decisions: [String: Decision],
        excluded: Set<String>,
        settings: AppSettings
    ) -> [Suggestion] {
        let learning = status(decisions: decisions, settings: settings)
        guard learning.isReady else { return [] }

        // Exemples d'apprentissage
        var trainVectors: [[Float]] = []
        var trainIsDelete: [Bool] = []
        var dimension = 0
        for d in decisions.values {
            guard let data = d.vectorData else { continue }
            let v = VectorMath.vector(from: data)
            guard !v.isEmpty else { continue }
            if dimension == 0 { dimension = v.count }
            guard v.count == dimension else { continue }
            trainVectors.append(v)
            trainIsDelete.append(d.kind == .delete)
        }
        guard !trainVectors.isEmpty else { return [] }

        // Photos candidates : jamais triées, pas favorites, pas déjà mises de côté
        let candidates = photos.filter {
            !$0.isFavorite && decisions[$0.id] == nil && !excluded.contains($0.id)
                && (vectors[$0.id]?.count ?? 0) == dimension
        }
        guard !candidates.isEmpty else { return [] }

        var suggestions: [Suggestion] = []
        let chunk = 256
        var start = 0
        while start < candidates.count {
            let end = min(start + chunk, candidates.count)
            let slice = Array(candidates[start..<end])
            let queries = slice.map { vectors[$0.id]! }
            let sims = VectorMath.similarityMatrix(queries: queries, base: trainVectors, dimension: dimension)
            let n = trainVectors.count

            for (row, photo) in slice.enumerated() {
                // Les k voisins les plus ressemblants
                var best: [(sim: Float, isDelete: Bool)] = []
                best.reserveCapacity(neighbourCount + 1)
                for j in 0..<n {
                    let s = sims[row * n + j]
                    guard s >= minRelevance else { continue }
                    if best.count < neighbourCount {
                        best.append((s, trainIsDelete[j]))
                        if best.count == neighbourCount { best.sort { $0.sim > $1.sim } }
                    } else if s > best[neighbourCount - 1].sim {
                        best[neighbourCount - 1] = (s, trainIsDelete[j])
                        best.sort { $0.sim > $1.sim }
                    }
                }
                guard best.count >= minNeighbours else { continue }

                var deleteWeight = 0.0, totalWeight = 0.0, deleted = 0
                for b in best {
                    let w = Double(b.sim)
                    totalWeight += w
                    if b.isDelete { deleteWeight += w; deleted += 1 }
                }
                // Prudence : on « tire » le score vers 50 % quand il y a peu de voisins.
                let confidence = (deleteWeight + 0.25) / (totalWeight + 0.5)
                if confidence >= settings.suggestionConfidence {
                    suggestions.append(Suggestion(
                        id: photo.id,
                        confidence: confidence,
                        similarCount: best.count,
                        deletedNeighbours: deleted
                    ))
                }
            }
            start = end
        }
        return suggestions.sorted { $0.confidence > $1.confidence }
    }
}
