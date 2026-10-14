import Foundation

/// Informations sur une photo ou une vidéo de la photothèque.
struct PhotoInfo: Codable, Sendable, Identifiable {
    var id: String
    var creationDate: Date?
    var isVideo: Bool
    var isScreenshot: Bool
    var isFavorite: Bool
    var burstID: String?
    /// Photo choisie (ou représentative) dans une rafale.
    var isBurstPick: Bool
    /// Taille estimée sur l'appareil / iCloud, en octets.
    var fileSize: Int64
    var duration: Double
    var pixelWidth: Int
    var pixelHeight: Int
    var analysis: PhotoAnalysis?

    init(
        id: String,
        creationDate: Date? = nil,
        isVideo: Bool = false,
        isScreenshot: Bool = false,
        isFavorite: Bool = false,
        burstID: String? = nil,
        isBurstPick: Bool = false,
        fileSize: Int64 = 0,
        duration: Double = 0,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0,
        analysis: PhotoAnalysis? = nil
    ) {
        self.id = id
        self.creationDate = creationDate
        self.isVideo = isVideo
        self.isScreenshot = isScreenshot
        self.isFavorite = isFavorite
        self.burstID = burstID
        self.isBurstPick = isBurstPick
        self.fileSize = fileSize
        self.duration = duration
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.analysis = analysis
    }
}

/// Résultat de l'analyse d'une image par l'IA d'Apple (Vision).
struct PhotoAnalysis: Codable, Sendable {
    static let currentVersion = 1

    var version: Int
    /// Empreinte de l'image (vecteur Float32 normalisé), stockée en binaire.
    var vectorData: Data
    /// Score esthétique d'Apple, de -1 (mauvais) à 1 (excellent).
    var aesthetic: Float?
    /// Photo « utilitaire » (document, ticket, capture…).
    var isUtility: Bool
    /// Netteté (variance du laplacien, plus c'est haut plus c'est net).
    var sharpness: Float
    /// Qualité d'exposition, de 0 (mauvaise) à 1 (parfaite).
    var exposure: Float
    /// Qualité moyenne des visages (0…1), nil s'il n'y a pas de visage.
    var faceQuality: Float?
    /// Ce que l'IA reconnaît dans l'image (identifiants anglais de Vision).
    var labels: [String]

    var vector: [Float] { VectorMath.vector(from: vectorData) }
}

enum DecisionKind: String, Codable, Sendable {
    case keep
    case delete
}

enum DecisionSource: String, Codable, Sendable {
    case swipe, series, cleanup, suggestion, album, favorite, external
}

/// Un choix de l'utilisateur (garder / supprimer), mémorisé pour apprendre.
struct Decision: Codable, Sendable {
    var kind: DecisionKind
    var date: Date
    /// Empreinte de la photo au moment du choix (conservée même après suppression).
    var vectorData: Data?
    var source: DecisionSource
}

struct AppSettings: Codable, Sendable, Equatable {
    /// Confiance minimale pour suggérer une suppression (0.8 = 80 %).
    var suggestionConfidence: Double = 0.8
    /// Ressemblance minimale pour former une série (0…1).
    var seriesSimilarity: Double = 0.88
    /// Écart maximal entre deux photos d'une même série, en secondes.
    var seriesMaxGap: Double = 900
    /// Seuil des « grosses vidéos », en Mo.
    var largeVideoMB: Double = 100
    /// Apprendre des suppressions faites dans l'app Photos.
    var learnFromExternalDeletions: Bool = true
    /// Nombre de choix nécessaires avant les premières suggestions.
    var minDecisionsForSuggestions: Int = 30

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.default
        suggestionConfidence = try c.decodeIfPresent(Double.self, forKey: .suggestionConfidence) ?? d.suggestionConfidence
        seriesSimilarity = try c.decodeIfPresent(Double.self, forKey: .seriesSimilarity) ?? d.seriesSimilarity
        seriesMaxGap = try c.decodeIfPresent(Double.self, forKey: .seriesMaxGap) ?? d.seriesMaxGap
        largeVideoMB = try c.decodeIfPresent(Double.self, forKey: .largeVideoMB) ?? d.largeVideoMB
        learnFromExternalDeletions = try c.decodeIfPresent(Bool.self, forKey: .learnFromExternalDeletions) ?? d.learnFromExternalDeletions
        minDecisionsForSuggestions = try c.decodeIfPresent(Int.self, forKey: .minDecisionsForSuggestions) ?? d.minDecisionsForSuggestions
    }

    static let `default` = AppSettings()
}

/// Tout ce que l'app mémorise entre deux lancements.
struct PersistedState: Codable, Sendable {
    var photos: [String: PhotoInfo] = [:]
    var decisions: [String: Decision] = [:]
    /// Photos mises de côté (glissées à gauche) en attente de suppression.
    var basket: [String] = []
    /// Propositions d'albums refusées (identifiant de l'étiquette).
    var dismissedAlbums: [String] = []
    var settings = AppSettings()
    /// Espace total libéré grâce à l'app, en octets.
    var freedBytes: Int64 = 0
    var deletedCount: Int = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        photos = try c.decodeIfPresent([String: PhotoInfo].self, forKey: .photos) ?? [:]
        decisions = try c.decodeIfPresent([String: Decision].self, forKey: .decisions) ?? [:]
        basket = try c.decodeIfPresent([String].self, forKey: .basket) ?? []
        dismissedAlbums = try c.decodeIfPresent([String].self, forKey: .dismissedAlbums) ?? []
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        freedBytes = try c.decodeIfPresent(Int64.self, forKey: .freedBytes) ?? 0
        deletedCount = try c.decodeIfPresent(Int.self, forKey: .deletedCount) ?? 0
    }
}
