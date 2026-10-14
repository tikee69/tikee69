import Foundation

/// Groupe de photos prises au même moment et qui se ressemblent fortement.
struct PhotoSeries: Identifiable, Sendable {
    var id: String
    /// Photos de la série, dans l'ordre chronologique.
    var photoIDs: [String]
    /// Photos que l'app conseille de garder (les plus belles).
    var keepIDs: Set<String>
    /// Note de beauté (0…1) de chaque photo.
    var scores: [String: Double]
    /// Pourquoi la meilleure photo a été choisie.
    var bestReasons: [String]
    var bestID: String
    var date: Date?
    /// Espace libéré si on supprime les photos non conservées.
    var reclaimableBytes: Int64
}

/// Note la beauté des photos d'un groupe, les unes par rapport aux autres.
enum BeautyScorer {
    struct Result: Sendable {
        var scores: [String: Double]
        var ranking: [String]
        var bestReasons: [String]
    }

    static func score(_ photos: [PhotoInfo]) -> Result {
        let analysed = photos.filter { $0.analysis != nil }
        guard !analysed.isEmpty else {
            return Result(scores: [:], ranking: photos.map(\.id), bestReasons: [])
        }

        let maxSharp = max(analysed.map { Double($0.analysis!.sharpness) }.max() ?? 0, 1)
        let hasFaces = analysed.contains { $0.analysis!.faceQuality != nil }

        var scores: [String: Double] = [:]
        for p in analysed {
            let a = p.analysis!
            let aesthetic = (Double(a.aesthetic ?? 0) + 1) / 2              // 0…1
            let sharp = min(Double(a.sharpness) / maxSharp, 1)             // 0…1, relatif au groupe
            let exposure = Double(a.exposure)                              // 0…1
            var total: Double
            if hasFaces {
                let face = Double(a.faceQuality ?? 0)
                total = aesthetic * 0.35 + sharp * 0.25 + exposure * 0.15 + face * 0.25
            } else {
                total = aesthetic * 0.45 + sharp * 0.35 + exposure * 0.20
            }
            if p.isFavorite { total += 1 }
            scores[p.id] = total
        }
        for p in photos where scores[p.id] == nil { scores[p.id] = -1 }

        let ranking = photos.map(\.id).sorted { (scores[$0] ?? -1) > (scores[$1] ?? -1) }

        // Explications pour la meilleure photo
        var reasons: [String] = []
        if let best = analysed.first(where: { $0.id == ranking.first }), let a = best.analysis {
            if best.isFavorite { reasons.append("Dans vos favoris") }
            if a.sharpness >= (analysed.map { $0.analysis!.sharpness }.max() ?? 0) { reasons.append("La plus nette") }
            if a.exposure >= (analysed.map { $0.analysis!.exposure }.max() ?? 0) - 0.02 { reasons.append("Bien exposée") }
            if let ae = a.aesthetic, ae >= (analysed.compactMap { $0.analysis!.aesthetic }.max() ?? ae) { reasons.append("La plus esthétique") }
            if let fq = a.faceQuality, fq >= (analysed.compactMap { $0.analysis!.faceQuality }.max() ?? fq) { reasons.append("Visages les plus réussis") }
            if reasons.isEmpty { reasons.append("Meilleur équilibre général") }
        }
        return Result(scores: scores, ranking: ranking, bestReasons: reasons)
    }
}

enum SeriesFinder {
    /// Trouve les séries de photos très ressemblantes prises à peu d'intervalle.
    static func find(
        photos: [PhotoInfo],
        vectors: [String: [Float]],
        similarity threshold: Double,
        maxGap: TimeInterval
    ) -> [PhotoSeries] {
        let candidates = photos
            .filter { !$0.isVideo && $0.creationDate != nil && vectors[$0.id] != nil }
            .sorted { $0.creationDate! < $1.creationDate! }

        var groups: [[PhotoInfo]] = []
        var current: [PhotoInfo] = []

        func closeCurrent() {
            if current.count >= 2 { groups.append(current) }
            current = []
        }

        for photo in candidates {
            guard let last = current.last else {
                current = [photo]
                continue
            }
            let gap = photo.creationDate!.timeIntervalSince(last.creationDate!)
            var belongs = false
            if let burst = photo.burstID, current.contains(where: { $0.burstID == burst }) {
                belongs = true
            } else if gap <= maxGap, let v = vectors[photo.id] {
                // Compare avec les 5 dernières photos du groupe
                for other in current.suffix(5) {
                    if let ov = vectors[other.id], Double(VectorMath.similarity(v, ov)) >= threshold {
                        belongs = true
                        break
                    }
                }
            }
            if belongs {
                current.append(photo)
            } else {
                closeCurrent()
                current = [photo]
            }
        }
        closeCurrent()

        return groups.map { makeSeries($0, vectors: vectors) }
    }

    static func makeSeries(_ group: [PhotoInfo], vectors: [String: [Float]]) -> PhotoSeries {
        let result = BeautyScorer.score(group)
        let ranking = result.ranking
        let best = ranking[0]
        var keep: Set<String> = [best]

        // Une deuxième photo si la série est grande et que la 2e est presque aussi belle
        // tout en étant un peu différente de la première.
        if group.count >= 4, ranking.count >= 2 {
            let second = ranking[1]
            let s1 = result.scores[best] ?? 0
            let s2 = result.scores[second] ?? 0
            let sim = Double(VectorMath.similarity(vectors[best] ?? [], vectors[second] ?? []))
            if s1 - s2 <= 0.06 && sim < 0.97 {
                keep.insert(second)
            }
        }
        // Les favoris sont toujours gardés.
        for p in group where p.isFavorite { keep.insert(p.id) }

        let reclaimable = group.filter { !keep.contains($0.id) }.reduce(Int64(0)) { $0 + $1.fileSize }
        return PhotoSeries(
            id: group[0].id,
            photoIDs: group.map(\.id),
            keepIDs: keep,
            scores: result.scores,
            bestReasons: result.bestReasons,
            bestID: best,
            date: group[0].creationDate,
            reclaimableBytes: reclaimable
        )
    }
}
