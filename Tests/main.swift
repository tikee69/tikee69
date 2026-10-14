// Tests de la logique de Pétale (sans iPhone), lancés automatiquement par GitHub.
// Compilation : swiftc Petale/Core/*.swift Tests/main.swift -o logictests && ./logictests
import Foundation

var failures = 0
func check(_ condition: Bool, _ message: String, line: Int = #line) {
    if condition {
        print("✅ \(message)")
    } else {
        print("❌ \(message) (ligne \(line))")
        failures += 1
    }
}

let dim = 16
func vec(_ seed: Int, noise: Float = 0) -> [Float] {
    var v = [Float](repeating: 0, count: dim)
    v[seed % dim] = 1
    v[(seed * 7 + 3) % dim] += 0.5
    for i in 0..<dim { v[i] += noise * Float((i * 31 + seed) % 7) / 7 }
    return VectorMath.normalized(v)
}

func photo(_ id: String, _ v: [Float], date: Date, sharp: Float = 300, aesthetic: Float = 0, exposure: Float = 0.8,
           favorite: Bool = false, size: Int64 = 3_000_000, screenshot: Bool = false, video: Bool = false,
           utility: Bool = false, labels: [String] = []) -> PhotoInfo {
    PhotoInfo(
        id: id, creationDate: date, isVideo: video, isScreenshot: screenshot, isFavorite: favorite,
        fileSize: size,
        analysis: PhotoAnalysis(version: 1, vectorData: VectorMath.data(from: v), aesthetic: aesthetic,
                                isUtility: utility, sharpness: sharp, exposure: exposure, faceQuality: nil, labels: labels)
    )
}

let t0 = Date(timeIntervalSince1970: 1_700_000_000)

// MARK: Vecteurs
do {
    let a = vec(1)
    check(abs(VectorMath.similarity(a, a) - 1) < 0.001, "Une photo se ressemble à 100 % à elle-même")
    check(VectorMath.similarity(vec(1), vec(2)) < 0.5, "Deux photos différentes se ressemblent peu")
    let back = VectorMath.vector(from: VectorMath.data(from: a))
    check(back == a, "L'empreinte est bien sauvegardée puis relue")
    let m = VectorMath.similarityMatrix(queries: [vec(1), vec(2)], base: [vec(1), vec(2), vec(3)], dimension: dim)
    check(m.count == 6, "La matrice de ressemblance a la bonne taille")
    check(abs(m[0] - 1) < 0.001 && abs(m[4] - 1) < 0.001, "La matrice de ressemblance est correcte")
    check(abs(m[1] - VectorMath.similarity(vec(1), vec(2))) < 0.001, "La matrice correspond au calcul simple")
    check(VectorMath.stableHash("abc") == VectorMath.stableHash("abc"), "Le hachage est stable")
}

// MARK: Séries et meilleure photo
do {
    var photos: [PhotoInfo] = []
    // Série de 5 photos quasi identiques, la n°2 est la plus nette et la plus belle
    for i in 0..<5 {
        photos.append(photo("s\(i)", vec(1, noise: Float(i) * 0.02), date: t0.addingTimeInterval(Double(i) * 5),
                            sharp: i == 2 ? 900 : 200, aesthetic: i == 2 ? 0.6 : -0.1))
    }
    // Photo différente juste après
    photos.append(photo("other", vec(5), date: t0.addingTimeInterval(30)))
    // Photo identique mais 2 jours plus tard : pas dans la série
    photos.append(photo("later", vec(1), date: t0.addingTimeInterval(172_800)))

    var vectors: [String: [Float]] = [:]
    for p in photos { vectors[p.id] = p.analysis!.vector }

    let series = SeriesFinder.find(photos: photos, vectors: vectors, similarity: 0.9, maxGap: 900)
    check(series.count == 1, "Une seule série trouvée (\(series.count))")
    if let s = series.first {
        check(s.photoIDs == ["s0", "s1", "s2", "s3", "s4"], "La série contient les 5 bonnes photos")
        check(s.bestID == "s2", "La photo la plus nette et belle est choisie comme meilleure")
        check(s.keepIDs.contains("s2"), "La meilleure photo est gardée")
        check(s.keepIDs.count <= 2, "On garde 1 ou 2 photos maximum")
        check(s.reclaimableBytes == Int64(5 - s.keepIDs.count) * 3_000_000, "L'espace récupérable est correct")
        check(s.bestReasons.contains("La plus nette"), "La raison « La plus nette » est donnée")
    }

    // Une favorite est toujours gardée
    var withFav = photos
    withFav[4].isFavorite = true
    let favSeries = SeriesFinder.find(photos: withFav, vectors: vectors, similarity: 0.9, maxGap: 900)
    check(favSeries.first?.keepIDs.contains("s4") == true, "Une photo favorite est toujours gardée")

    // Deux photos de qualité égale et un peu différentes : on en garde 2
    var twins: [PhotoInfo] = []
    for i in 0..<5 {
        twins.append(photo("t\(i)", vec(3, noise: Float(i) * 0.2), date: t0.addingTimeInterval(Double(i)),
                           sharp: i < 2 ? 800 : 100, aesthetic: i < 2 ? 0.5 : -0.5))
    }
    var tv: [String: [Float]] = [:]
    for p in twins { tv[p.id] = p.analysis!.vector }
    let twinSeries = SeriesFinder.find(photos: twins, vectors: tv, similarity: 0.85, maxGap: 900)
    check(twinSeries.first?.keepIDs == ["t0", "t1"], "Deux photos aussi belles l'une que l'autre sont gardées")
}

// MARK: Apprentissage
do {
    var settings = AppSettings()
    settings.minDecisionsForSuggestions = 10
    var decisions: [String: Decision] = [:]
    // L'utilisateur supprime les photos du type 1 et garde celles du type 2
    for i in 0..<8 {
        decisions["del\(i)"] = Decision(kind: .delete, date: t0, vectorData: VectorMath.data(from: vec(1, noise: Float(i) * 0.01)), source: .swipe)
        decisions["keep\(i)"] = Decision(kind: .keep, date: t0, vectorData: VectorMath.data(from: vec(2, noise: Float(i) * 0.01)), source: .swipe)
    }
    let candidates = [
        photo("like-deleted", vec(1, noise: 0.015), date: t0),
        photo("like-kept", vec(2, noise: 0.015), date: t0),
        photo("unknown", vec(9), date: t0),
        photo("fav", vec(1, noise: 0.015), date: t0, favorite: true),
    ]
    var vectors: [String: [Float]] = [:]
    for p in candidates { vectors[p.id] = p.analysis!.vector }

    let status = SuggestionEngine.status(decisions: decisions, settings: settings)
    check(status.isReady, "L'apprentissage est prêt après assez de choix")

    let sugg = SuggestionEngine.suggest(photos: candidates, vectors: vectors, decisions: decisions, excluded: [], settings: settings)
    let ids = Set(sugg.map(\.id))
    check(ids.contains("like-deleted"), "Une photo semblable aux supprimées est suggérée")
    check(!ids.contains("like-kept"), "Une photo semblable aux gardées n'est pas suggérée")
    check(!ids.contains("unknown"), "Une photo sans ressemblance n'est pas suggérée")
    check(!ids.contains("fav"), "Une favorite n'est jamais suggérée")
    check((sugg.first?.confidence ?? 0) >= 0.8, "La confiance dépasse 80 %")

    let notReady = SuggestionEngine.suggest(photos: candidates, vectors: vectors, decisions: [:], excluded: [], settings: settings)
    check(notReady.isEmpty, "Aucune suggestion sans apprentissage")
}

// MARK: Catégories et albums
do {
    var photos = [
        photo("shot", vec(1), date: t0, screenshot: true),
        photo("blur", vec(2), date: t0, sharp: 10),
        photo("sharp", vec(3), date: t0, sharp: 800),
        photo("doc", vec(4), date: t0, utility: true),
        photo("bigvid", vec(5), date: t0, size: 500_000_000, video: true),
        photo("smallvid", vec(6), date: t0, size: 5_000_000, video: true),
    ]
    var burst = photo("burst", vec(7), date: t0)
    burst.burstID = "B1"
    burst.isBurstPick = false
    photos.append(burst)

    let groups = Dictionary(uniqueKeysWithValues: CleanupFinder.groups(photos: photos, settings: AppSettings()).map { ($0.kind, $0) })
    check(groups[.screenshots]?.ids == ["shot"], "Les captures d'écran sont trouvées")
    check(groups[.blurry]?.ids == ["blur"], "Les photos floues sont trouvées")
    check(groups[.documents]?.ids == ["doc"], "Les documents sont trouvés")
    check(groups[.largeVideos]?.ids == ["bigvid"], "Les grosses vidéos sont trouvées")
    check(groups[.bursts]?.ids == ["burst"], "Les rafales non choisies sont trouvées")

    var albumPhotos: [PhotoInfo] = []
    for i in 0..<15 { albumPhotos.append(photo("dog\(i)", vec(1), date: t0, labels: ["dog", "outdoor"])) }
    for i in 0..<5 { albumPhotos.append(photo("cat\(i)", vec(2), date: t0, labels: ["cat"])) }
    let albums = AlbumSuggester.proposals(photos: albumPhotos, dismissed: [])
    check(albums.map(\.id) == ["dog"], "L'album « Chiens » est proposé, pas les étiquettes générales")
    check(albums.first?.title == "Chiens", "Le nom de l'album est en français")
    check(AlbumSuggester.proposals(photos: albumPhotos, dismissed: ["dog"]).isEmpty, "Un album refusé n'est plus proposé")
}

// MARK: Sauvegarde
do {
    var state = PersistedState()
    state.photos["a"] = photo("a", vec(1), date: t0)
    state.decisions["b"] = Decision(kind: .delete, date: t0, vectorData: VectorMath.data(from: vec(2)), source: .external)
    state.basket = ["a"]
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    let data = try! encoder.encode(state)
    let decoded = try! PropertyListDecoder().decode(PersistedState.self, from: data)
    check(decoded.photos["a"]?.analysis?.vector == vec(1), "Les photos sont bien sauvegardées")
    check(decoded.decisions["b"]?.kind == .delete, "Les choix sont bien sauvegardés")
    check(decoded.basket == ["a"], "La corbeille est bien sauvegardée")

    // Ancien format sans certains champs : ne doit pas planter
    let partial = try! PropertyListSerialization.data(fromPropertyList: ["basket": ["x"]], format: .binary, options: 0)
    let p = try? PropertyListDecoder().decode(PersistedState.self, from: partial)
    check(p?.basket == ["x"] && p?.settings == AppSettings(), "Un fichier incomplet est relu sans erreur")

    let insights = Insights.compute(state: decoded)
    check(insights.reclaimableBytes == 3_000_000, "L'espace récupérable compte la corbeille")
}

print(failures == 0 ? "\nTous les tests sont passés 🎉" : "\n\(failures) test(s) en échec")
exit(failures == 0 ? 0 : 1)
