import Foundation

enum CleanupKind: String, CaseIterable, Identifiable, Sendable {
    case screenshots, blurry, bursts, documents, largeVideos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screenshots: return "Captures d'écran"
        case .blurry: return "Photos floues"
        case .bursts: return "Rafales"
        case .documents: return "Documents et tickets"
        case .largeVideos: return "Grosses vidéos"
        }
    }

    var subtitle: String {
        switch self {
        case .screenshots: return "Souvent utiles un jour, inutiles ensuite."
        case .blurry: return "Photos floues ou ratées repérées par l'IA."
        case .bursts: return "Images d'une rafale que vous n'avez pas choisies."
        case .documents: return "Papiers, tickets, tableaux, notes…"
        case .largeVideos: return "Les vidéos qui prennent le plus de place."
        }
    }

    var systemImage: String {
        switch self {
        case .screenshots: return "camera.viewfinder"
        case .blurry: return "drop.halffull"
        case .bursts: return "square.stack.3d.down.forward"
        case .documents: return "doc.text.viewfinder"
        case .largeVideos: return "video"
        }
    }
}

struct CleanupGroup: Identifiable, Sendable {
    var kind: CleanupKind
    var ids: [String]
    var bytes: Int64
    var id: String { kind.rawValue }
}

enum CleanupFinder {
    /// Seuils de netteté (variance du laplacien sur une image de 256 px).
    static let blurryHard: Float = 40
    static let blurrySoft: Float = 110

    static func isBlurry(_ p: PhotoInfo) -> Bool {
        guard !p.isVideo, !p.isScreenshot, let a = p.analysis, !a.isUtility else { return false }
        if a.sharpness < blurryHard { return true }
        if a.sharpness < blurrySoft, let ae = a.aesthetic, ae < -0.2 { return true }
        return false
    }

    static func groups(photos: [PhotoInfo], settings: AppSettings) -> [CleanupGroup] {
        let sortedByDate = photos.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        let largeLimit = Int64(settings.largeVideoMB * 1_000_000)

        var result: [CleanupGroup] = []
        for kind in CleanupKind.allCases {
            var items: [PhotoInfo]
            switch kind {
            case .screenshots:
                items = sortedByDate.filter { $0.isScreenshot && !$0.isFavorite }
            case .blurry:
                items = sortedByDate.filter { !$0.isFavorite && isBlurry($0) }
            case .bursts:
                items = sortedByDate.filter { $0.burstID != nil && !$0.isBurstPick && !$0.isFavorite }
            case .documents:
                items = sortedByDate.filter {
                    !$0.isVideo && !$0.isScreenshot && !$0.isFavorite && ($0.analysis?.isUtility ?? false)
                }
            case .largeVideos:
                items = photos.filter { $0.isVideo && !$0.isFavorite && $0.fileSize >= largeLimit }
                    .sorted { $0.fileSize > $1.fileSize }
            }
            let bytes = items.reduce(Int64(0)) { $0 + $1.fileSize }
            result.append(CleanupGroup(kind: kind, ids: items.map(\.id), bytes: bytes))
        }
        return result
    }
}

// MARK: - Albums

struct AlbumProposal: Identifiable, Sendable {
    /// Identifiant de l'étiquette Vision (ex. « dog »).
    var id: String
    var title: String
    var symbol: String
    var ids: [String]
}

enum AlbumSuggester {
    static let minimumPhotos = 12
    static let maximumProposals = 15

    static func proposals(photos: [PhotoInfo], dismissed: Set<String>) -> [AlbumProposal] {
        var byLabel: [String: [PhotoInfo]] = [:]
        for p in photos {
            guard let labels = p.analysis?.labels else { continue }
            for label in labels where !LabelCatalog.ignored.contains(label) && !dismissed.contains(label) {
                byLabel[label, default: []].append(p)
            }
        }

        var candidates = byLabel
            .filter { $0.value.count >= minimumPhotos }
            .map { label, items -> AlbumProposal in
                let sorted = items.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
                return AlbumProposal(
                    id: label,
                    title: LabelCatalog.title(for: label),
                    symbol: LabelCatalog.symbol(for: label),
                    ids: sorted.map(\.id)
                )
            }
            .sorted {
                // Les étiquettes traduites d'abord (plus parlantes), puis les plus grandes.
                let k0 = LabelCatalog.french[$0.id] != nil, k1 = LabelCatalog.french[$1.id] != nil
                if k0 != k1 { return k0 }
                return $0.ids.count > $1.ids.count
            }

        // On évite les doublons (ex. « Plage » et « Mer » avec les mêmes photos).
        var kept: [AlbumProposal] = []
        for c in candidates {
            let set = Set(c.ids)
            let overlaps = kept.contains { k in
                let inter = set.intersection(k.ids).count
                return Double(inter) / Double(min(set.count, k.ids.count)) > 0.7
            }
            if !overlaps { kept.append(c) }
            if kept.count >= maximumProposals { break }
        }
        candidates = kept
        return candidates
    }
}

/// Traduction des étiquettes de l'IA d'Apple.
enum LabelCatalog {
    /// Étiquettes trop générales pour faire un bon album.
    static let ignored: Set<String> = [
        "outdoor", "indoor", "structure", "sky", "blue_sky", "cloudy", "clouds", "people", "adult",
        "material", "textile", "wood_processed", "raw_glass", "grass", "land", "liquid", "water",
        "water_body", "interior_room", "room", "machine", "conveyance", "vehicle", "night", "daytime",
        "plant", "foliage", "tree", "wall", "floor", "ceiling", "window", "furniture", "light",
        "lighting", "screenshot", "text", "document", "paper", "consumer_electronics", "computer",
        "electronics", "tool", "container", "clothing", "apparel", "footwear", "accessories", "jewelry",
        "hand", "finger", "arm", "leg", "face", "head", "hair", "shadow", "pattern", "art", "cord",
        "road", "street", "path", "sign", "signage", "shelf", "table", "chair", "decoration", "metal",
        "plastic", "fabric", "rock", "stone", "dirt", "sand", "wood", "brick", "concrete", "glass",
        "housewares", "kitchenware", "utensil", "tableware", "bottle", "cup", "office_supplies",
        "screen", "monitor", "display", "phone", "cellphone", "printed_page", "receipt", "handwriting",
        "illustrations", "cartoon", "logo", "graph", "chart", "diagram",
    ]

    static let french: [String: String] = [
        "dog": "Chiens", "cat": "Chats", "bird": "Oiseaux", "horse": "Chevaux", "animal": "Animaux",
        "pet": "Animaux de compagnie", "fish": "Poissons", "insect": "Insectes", "butterfly": "Papillons",
        "beach": "Plage", "ocean": "Mer et océan", "sea": "Mer", "lake": "Lac", "river": "Rivière",
        "waterfall": "Cascades", "mountain": "Montagne", "hill": "Collines", "snow": "Neige",
        "forest": "Forêt", "desert": "Désert", "sunset_sunrise": "Couchers de soleil", "sunset": "Couchers de soleil",
        "sunrise": "Levers de soleil", "flower": "Fleurs", "garden": "Jardin", "park": "Parcs",
        "food": "Nourriture", "meal": "Repas", "dessert": "Desserts", "cake": "Gâteaux", "pizza": "Pizzas",
        "fruit": "Fruits", "vegetable": "Légumes", "bread": "Pain", "drink": "Boissons", "wine": "Vin",
        "beer": "Bière", "coffee": "Café", "cocktail": "Cocktails", "sushi": "Sushis", "burger": "Burgers",
        "car": "Voitures", "motorcycle": "Motos", "bicycle": "Vélos", "airplane": "Avions", "aircraft": "Avions",
        "boat": "Bateaux", "train": "Trains", "building": "Bâtiments", "cityscape": "Villes",
        "city": "Villes", "skyscraper": "Gratte-ciel", "bridge": "Ponts", "church": "Églises",
        "castle": "Châteaux", "monument": "Monuments", "museum": "Musées", "restaurant": "Restaurants",
        "baby": "Bébés", "child": "Enfants", "kid": "Enfants", "selfie": "Selfies", "portrait": "Portraits",
        "crowd": "Foules", "wedding": "Mariages", "party": "Fêtes", "birthday": "Anniversaires",
        "christmas": "Noël", "christmas_tree": "Noël", "fireworks": "Feux d'artifice", "concert": "Concerts",
        "sport": "Sport", "soccer": "Football", "football": "Football", "basketball": "Basket",
        "tennis": "Tennis", "ski": "Ski", "skiing": "Ski", "swimming_pool": "Piscine", "pool": "Piscine",
        "surfing": "Surf", "hiking": "Randonnée", "camping": "Camping", "night_sky": "Ciel nocturne",
        "moon": "Lune", "rainbow": "Arcs-en-ciel", "painting": "Peintures", "sculpture": "Sculptures",
        "statue": "Statues", "graffiti": "Graffitis", "car_interior": "Intérieur de voiture",
        "kitchen": "Cuisine", "bedroom": "Chambre", "living_room": "Salon", "toy": "Jouets",
        "book": "Livres", "musical_instrument": "Instruments de musique", "guitar": "Guitare",
        "piano": "Piano", "shoes": "Chaussures", "game": "Jeux", "video_game": "Jeux vidéo",
    ]

    static func title(for label: String) -> String {
        if let fr = french[label] { return fr }
        let cleaned = label.replacingOccurrences(of: "_", with: " ")
        return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
    }

    static func symbol(for label: String) -> String {
        switch label {
        case "dog": return "dog.fill"
        case "cat": return "cat.fill"
        case "bird": return "bird.fill"
        case "horse": return "hare.fill"
        case "animal", "pet", "fish", "insect", "butterfly": return "pawprint.fill"
        case "beach", "ocean", "sea", "lake", "river", "waterfall", "swimming_pool", "pool", "surfing": return "water.waves"
        case "mountain", "hill", "hiking", "camping", "desert": return "mountain.2.fill"
        case "snow", "ski", "skiing": return "snowflake"
        case "forest", "garden", "park", "flower": return "leaf.fill"
        case "sunset_sunrise", "sunset", "sunrise": return "sun.horizon.fill"
        case "night_sky", "moon": return "moon.stars.fill"
        case "food", "meal", "dessert", "cake", "pizza", "fruit", "vegetable", "bread", "sushi", "burger", "restaurant", "kitchen": return "fork.knife"
        case "drink", "wine", "beer", "coffee", "cocktail": return "wineglass.fill"
        case "car", "car_interior": return "car.fill"
        case "motorcycle", "bicycle": return "bicycle"
        case "airplane", "aircraft": return "airplane"
        case "boat": return "ferry.fill"
        case "train": return "tram.fill"
        case "building", "cityscape", "city", "skyscraper", "bridge", "church", "castle", "monument", "museum": return "building.2.fill"
        case "baby", "child", "kid": return "figure.and.child.holdinghands"
        case "selfie", "portrait", "crowd": return "person.2.fill"
        case "wedding", "party", "birthday", "christmas", "christmas_tree", "fireworks", "concert": return "party.popper.fill"
        case "sport", "soccer", "football", "basketball", "tennis": return "figure.run"
        case "painting", "sculpture", "statue", "graffiti": return "paintpalette.fill"
        default: return "photo.on.rectangle.angled"
        }
    }
}
