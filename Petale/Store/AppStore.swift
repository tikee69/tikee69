import Observation
import Photos
import SwiftUI
import UIKit

/// Le cœur de l'app : garde l'état, lance les analyses et applique vos choix.
@MainActor
@Observable
final class AppStore {
    // MARK: État visible

    private(set) var state = PersistedState()
    private(set) var insights = Insights.empty
    private(set) var authorization: PHAuthorizationStatus = .notDetermined
    private(set) var isLoaded = false
    private(set) var isScanning = false
    private(set) var isAnalyzing = false
    private(set) var isComputing = false
    private(set) var analysisDone = 0
    private(set) var analysisTotal = 0
    var errorMessage: String?
    /// Message de confirmation affiché après une action (ex. « 12 photos supprimées »).
    var toast: String?

    var hasAccess: Bool { authorization == .authorized || authorization == .limited }
    var isLimited: Bool { authorization == .limited }

    // MARK: Interne

    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var insightsTask: Task<Void, Never>?
    @ObservationIgnored private var saveGeneration = 0
    private let writer = StateWriter()
    @ObservationIgnored private var failedAnalysis = Set<String>()
    @ObservationIgnored private var lastRefresh: Date?
    @ObservationIgnored private var refreshAgain = false

    // MARK: Démarrage

    func start() async {
        guard !isLoaded else { return }
        let loaded = await Task.detached(priority: .userInitiated) { Persistence.load() }.value
        state = loaded
        authorization = LibraryScanner.currentStatus()
        isLoaded = true
        recomputeInsights()
        if hasAccess { await refresh() }
    }

    func requestAccess() async {
        authorization = await LibraryScanner.requestAccess()
        if hasAccess { await refresh() }
    }

    func appBecameActive() {
        guard isLoaded else { return }
        let status = LibraryScanner.currentStatus()
        if status != authorization { authorization = status }
        guard hasAccess else { return }
        if let last = lastRefresh, Date().timeIntervalSince(last) < 5 { return }
        Task { await refresh() }
    }

    func appWentToBackground() {
        save()
    }

    // MARK: Lecture de la photothèque

    /// Met à jour la liste des photos et repère celles supprimées depuis la dernière fois.
    func refresh() async {
        guard hasAccess else { return }
        if isScanning {
            refreshAgain = true
            return
        }
        isScanning = true
        lastRefresh = Date()
        defer { isScanning = false }

        let existing = state.photos
        let scanned = await Task.detached(priority: .userInitiated) {
            LibraryScanner.scan(existing: existing)
        }.value

        var newPhotos: [String: PhotoInfo] = [:]
        newPhotos.reserveCapacity(scanned.count)
        for p in scanned { newPhotos[p.id] = p }

        // Photos disparues = supprimées par vous (dans Photos ou ailleurs).
        let missing = existing.keys.filter { newPhotos[$0] == nil }
        let looksNormal = missing.count <= max(50, existing.count / 3)
        if !missing.isEmpty, looksNormal, !isLimited, state.settings.learnFromExternalDeletions {
            for id in missing {
                guard let vectorData = existing[id]?.analysis?.vectorData else { continue }
                // Une photo déjà marquée « à garder » puis supprimée : on corrige.
                state.decisions[id] = Decision(kind: .delete, date: Date(), vectorData: vectorData, source: .external)
            }
        }
        if !missing.isEmpty {
            let missingSet = Set(missing)
            state.basket.removeAll { missingSet.contains($0) }
        }

        state.photos = newPhotos
        save()
        recomputeInsights()
        startAnalysis()

        if refreshAgain {
            refreshAgain = false
            Task { await refresh() }
        }
    }

    // MARK: Analyse par l'IA

    private func startAnalysis() {
        guard analysisTask == nil else { return }
        let pending = state.photos.values
            .filter { ($0.analysis?.version ?? 0) < PhotoAnalysis.currentVersion && !failedAnalysis.contains($0.id) }
            .sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
            .map(\.id)
        guard !pending.isEmpty else { return }

        analysisTotal = pending.count
        analysisDone = 0
        isAnalyzing = true
        UIApplication.shared.isIdleTimerDisabled = true

        analysisTask = Task { [weak self] in
            await self?.runAnalysis(ids: pending)
            guard let self else { return }
            self.analysisTask = nil
            self.isAnalyzing = false
            UIApplication.shared.isIdleTimerDisabled = false
            self.save()
            self.recomputeInsights()
            // De nouvelles photos sont peut-être arrivées pendant l'analyse.
            if self.state.photos.values.contains(where: {
                ($0.analysis?.version ?? 0) < PhotoAnalysis.currentVersion && !self.failedAnalysis.contains($0.id)
            }) {
                self.startAnalysis()
            }
        }
    }

    private func runAnalysis(ids: [String]) async {
        let concurrency = 3
        var pending: [(String, PhotoAnalysis?)] = []

        await withTaskGroup(of: (String, PhotoAnalysis?).self) { group in
            var iterator = ids.makeIterator()
            for _ in 0..<concurrency {
                if let id = iterator.next() {
                    group.addTask { (id, await PhotoAnalyzer.analyze(id: id)) }
                }
            }
            while let result = await group.next() {
                pending.append(result)
                if pending.count >= 20 {
                    await self.apply(pending)
                    pending.removeAll()
                }
                if Task.isCancelled {
                    group.cancelAll()
                    continue
                }
                if let id = iterator.next() {
                    group.addTask { (id, await PhotoAnalyzer.analyze(id: id)) }
                }
            }
        }
        apply(pending)
    }

    private func apply(_ results: [(String, PhotoAnalysis?)]) {
        guard !results.isEmpty else { return }
        for (id, analysis) in results {
            if let analysis {
                state.photos[id]?.analysis = analysis
            } else {
                failedAnalysis.insert(id)
            }
        }
        let before = analysisDone
        analysisDone += results.count
        // Résultats intermédiaires de temps en temps
        if before / 400 != analysisDone / 400 {
            save()
            recomputeInsights()
        }
    }

    /// Efface toutes les analyses et recommence (utile si les réglages d'IA changent).
    func reanalyzeEverything() {
        analysisTask?.cancel()
        analysisTask = nil
        for id in state.photos.keys { state.photos[id]?.analysis = nil }
        failedAnalysis.removeAll()
        save()
        recomputeInsights()
        startAnalysis()
    }

    // MARK: Déductions

    func recomputeInsights() {
        insightsTask?.cancel()
        let snapshot = state
        isComputing = true
        insightsTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return }
            let result = await Task.detached(priority: .utility) { Insights.compute(state: snapshot) }.value
            if Task.isCancelled { return }
            self?.insights = result
            self?.isComputing = false
        }
    }

    // MARK: Sauvegarde

    func save() {
        saveGeneration += 1
        let generation = saveGeneration
        let snapshot = state
        let writer = writer
        Task.detached(priority: .utility) {
            await writer.write(snapshot, generation: generation)
        }
    }

    // MARK: Accès pratiques

    func photo(_ id: String) -> PhotoInfo? { state.photos[id] }

    func bytes(of ids: some Sequence<String>) -> Int64 {
        ids.reduce(Int64(0)) { $0 + (state.photos[$1]?.fileSize ?? 0) }
    }

    var photoCount: Int { state.photos.values.filter { !$0.isVideo }.count }
    var videoCount: Int { state.photos.values.filter(\.isVideo).count }
    var analysedCount: Int { state.photos.values.filter { $0.analysis != nil }.count }

    // MARK: Apprentissage

    func record(_ kind: DecisionKind, ids: [String], source: DecisionSource) {
        var changed = false
        for id in ids {
            guard let photo = state.photos[id] else { continue }
            state.decisions[id] = Decision(
                kind: kind, date: Date(), vectorData: photo.analysis?.vectorData, source: source
            )
            changed = true
        }
        if changed {
            save()
            recomputeInsights()
        }
    }

    func clearDecision(_ id: String) {
        state.decisions[id] = nil
        save()
        recomputeInsights()
    }

    func resetLearning() {
        state.decisions.removeAll()
        save()
        recomputeInsights()
    }

    // MARK: Corbeille (photos glissées à gauche)

    var basket: [String] { state.basket }

    func addToBasket(_ id: String) {
        guard !state.basket.contains(id) else { return }
        state.basket.append(id)
        save()
    }

    func removeFromBasket(_ ids: [String]) {
        let set = Set(ids)
        state.basket.removeAll { set.contains($0) }
        save()
        recomputeInsights()
    }

    // MARK: Actions sur la photothèque

    /// Supprime des photos après confirmation d'iPhone. Retourne true si c'est fait.
    @discardableResult
    func delete(_ ids: [String], source: DecisionSource, alsoKeep keepIDs: [String] = []) async -> Bool {
        let unique = Array(Set(ids))
        guard !unique.isEmpty else {
            if !keepIDs.isEmpty { record(.keep, ids: keepIDs, source: source) }
            return true
        }
        do {
            guard let deleted = try await PhotoActions.delete(ids: unique) else {
                return false   // annulé par vous
            }
            let freed = bytes(of: deleted)
            let now = Date()
            for id in deleted {
                state.decisions[id] = Decision(
                    kind: .delete, date: now, vectorData: state.photos[id]?.analysis?.vectorData, source: source
                )
                state.photos[id] = nil
            }
            for id in keepIDs where state.photos[id] != nil {
                state.decisions[id] = Decision(
                    kind: .keep, date: now, vectorData: state.photos[id]?.analysis?.vectorData, source: source
                )
            }
            let deletedSet = Set(deleted)
            state.basket.removeAll { deletedSet.contains($0) }
            state.freedBytes += freed
            state.deletedCount += deleted.count
            save()
            recomputeInsights()
            let noun = deleted.count > 1 ? "éléments supprimés" : "élément supprimé"
            toast = "\(deleted.count) \(noun) · \(freed.formattedBytes) libérés"
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func toggleFavorite(_ id: String) async {
        guard let photo = state.photos[id] else { return }
        let newValue = !photo.isFavorite
        do {
            try await PhotoActions.setFavorite(id: id, newValue)
            state.photos[id]?.isFavorite = newValue
            if newValue {
                record(.keep, ids: [id], source: .favorite)
            } else {
                save()
                recomputeInsights()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createAlbum(_ proposal: AlbumProposal, title: String, ids: [String]) async -> Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await PhotoActions.createAlbum(title: cleanTitle.isEmpty ? proposal.title : cleanTitle, ids: ids)
            if !state.dismissedAlbums.contains(proposal.id) { state.dismissedAlbums.append(proposal.id) }
            record(.keep, ids: ids, source: .album)
            toast = "Album « \(cleanTitle.isEmpty ? proposal.title : cleanTitle) » créé"
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func dismissAlbum(_ proposal: AlbumProposal) {
        if !state.dismissedAlbums.contains(proposal.id) { state.dismissedAlbums.append(proposal.id) }
        save()
        recomputeInsights()
    }

    func restoreDismissedAlbums() {
        state.dismissedAlbums.removeAll()
        save()
        recomputeInsights()
    }

    // MARK: Réglages

    func updateSettings(_ settings: AppSettings) {
        guard settings != state.settings else { return }
        state.settings = settings
        save()
        recomputeInsights()
    }

    // MARK: File de tri

    /// Photos à présenter dans l'écran de tri : jamais triées, ordre aléatoire mais stable.
    func swipeCandidates(excluding: Set<String>, limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        let basket = Set(state.basket)
        let available = state.photos.values.filter {
            !$0.isFavorite && state.decisions[$0.id] == nil && !basket.contains($0.id) && !excluding.contains($0.id)
        }
        // On montre en priorité les suggestions de l'IA (pour confirmer ou corriger),
        // puis le reste dans un ordre mélangé.
        let suggested = Set(insights.suggestionByID.keys)
        return available
            .sorted { a, b in
                let sa = suggested.contains(a.id), sb = suggested.contains(b.id)
                if sa != sb { return sa }
                return VectorMath.stableHash(a.id) < VectorMath.stableHash(b.id)
            }
            .prefix(limit)
            .map(\.id)
    }
}
