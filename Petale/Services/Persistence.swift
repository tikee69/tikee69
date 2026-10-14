import Foundation

/// Enregistre la mémoire de l'app dans un fichier, à l'intérieur de l'app.
enum Persistence {
    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("petale-state.plist")
    }

    static func load() -> PersistedState {
        let url = fileURL
        guard let data = try? Data(contentsOf: url) else { return PersistedState() }
        do {
            return try PropertyListDecoder().decode(PersistedState.self, from: data)
        } catch {
            // Fichier illisible : on le met de côté au lieu de l'écraser.
            let backup = url.deletingLastPathComponent().appendingPathComponent("petale-state-illisible.plist")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: url, to: backup)
            return PersistedState()
        }
    }
}

/// Écrit les sauvegardes une par une, en arrière-plan, sans jamais revenir à une version plus ancienne.
actor StateWriter {
    private var lastWritten = 0

    func write(_ state: PersistedState, generation: Int) {
        guard generation > lastWritten else { return }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        do {
            let data = try encoder.encode(state)
            let url = Persistence.fileURL
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: url, options: [.atomic])
            lastWritten = generation
        } catch {
            print("Pétale : sauvegarde impossible – \(error)")
        }
    }
}
