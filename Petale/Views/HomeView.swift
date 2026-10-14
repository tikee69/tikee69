import SwiftUI

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Binding var selection: AppTab
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Espace récupérable")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(store.insights.reclaimableBytes.formattedBytes)
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(colors: [Color("AccentColor"), .orange],
                                               startPoint: .leading, endPoint: .trailing)
                            )
                            .contentTransition(.numericText())
                        if store.state.freedBytes > 0 {
                            Text("Déjà libéré avec Pétale : \(store.state.freedBytes.formattedBytes) (\(store.state.deletedCount) éléments)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                    AnalysisBanner()
                }

                if store.isLimited {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Accès limité", systemImage: "exclamationmark.triangle.fill")
                                .font(.headline)
                                .foregroundStyle(.orange)
                            Text("Pétale ne voit qu'une partie de vos photos. Pour tout analyser, choisissez « Accès complet » dans les Réglages.")
                                .font(.subheadline)
                            Button("Ouvrir les Réglages") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                        }
                    }
                }

                Section("À faire") {
                    shortcut(
                        title: "Trier en glissant",
                        detail: store.basket.isEmpty ? "Gauche : supprimer · Droite : garder" : "\(store.basket.count) en attente de suppression",
                        systemImage: "hand.draw.fill", color: .pink, tab: .swipe
                    )
                    shortcut(
                        title: "Séries de photos",
                        detail: seriesDetail,
                        systemImage: "square.stack.3d.down.right.fill", color: .purple, tab: .series
                    )
                    shortcut(
                        title: "Nettoyer",
                        detail: cleanupDetail,
                        systemImage: "sparkles", color: .blue, tab: .clean
                    )
                    shortcut(
                        title: "Suggestions",
                        detail: suggestionsDetail,
                        systemImage: "wand.and.stars", color: .orange, tab: .forYou
                    )
                }

                Section {
                    LearningRow(status: store.insights.learning)
                } header: {
                    Text("Apprentissage")
                } footer: {
                    Text("Pétale apprend de chaque photo que vous gardez ou supprimez, ici ou dans l'app Photos.")
                }

                Section("Votre photothèque") {
                    LabeledContent("Photos", value: "\(store.photoCount)")
                    LabeledContent("Vidéos", value: "\(store.videoCount)")
                    LabeledContent("Analysées par l'IA", value: "\(store.analysedCount)")
                    LabeledContent("Taille totale", value: store.bytes(of: store.state.photos.keys).formattedBytes)
                }
            }
            .navigationTitle("Pétale")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Réglages")
                }
            }
            .refreshable { await store.refresh() }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    private var seriesDetail: String {
        let count = store.insights.series.count
        if count == 0 { return "Aucune série pour l'instant" }
        return "\(count) séries · \(store.insights.seriesReclaimableCount) photos en trop"
    }

    private var cleanupDetail: String {
        let total = store.insights.cleanup.filter { $0.kind != .largeVideos }.reduce(0) { $0 + $1.ids.count }
        return total == 0 ? "Rien à nettoyer" : "\(total) photos à vérifier"
    }

    private var suggestionsDetail: String {
        let learning = store.insights.learning
        if !learning.isReady { return "Encore \(learning.remaining) tris pour activer l'IA" }
        let count = store.insights.suggestions.count
        return count == 0 ? "Aucune suggestion pour l'instant" : "\(count) photos suggérées"
    }

    private func shortcut(title: String, detail: String, systemImage: String, color: Color, tab: AppTab) -> some View {
        Button {
            selection = tab
        } label: {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct LearningRow: View {
    let status: LearningStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: status.isReady ? "brain.head.profile.fill" : "brain.head.profile")
                    .foregroundStyle(status.isReady ? Color.green : Color.secondary)
                Text(status.isReady ? "L'IA vous connaît" : "L'IA apprend à vous connaître")
                    .font(.headline)
            }
            if !status.isReady {
                ProgressView(value: status.progress)
                Text("Encore \(status.remaining) tris avant les premières suggestions.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text("\(status.keeps) photos gardées · \(status.deletes) supprimées")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var settings = AppSettings()
    @State private var confirmReset = false
    @State private var confirmReanalyze = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading) {
                        LabeledContent("Confiance minimale", value: settings.suggestionConfidence.percentString)
                        Slider(value: $settings.suggestionConfidence, in: 0.6...0.95, step: 0.05)
                    }
                    Stepper("Tris avant suggestions : \(settings.minDecisionsForSuggestions)",
                            value: $settings.minDecisionsForSuggestions, in: 10...200, step: 10)
                    Toggle("Apprendre des suppressions faites dans Photos", isOn: $settings.learnFromExternalDeletions)
                } header: {
                    Text("Suggestions")
                } footer: {
                    Text("Plus la confiance est haute, moins Pétale suggère, mais plus il est sûr de lui.")
                }

                Section {
                    VStack(alignment: .leading) {
                        LabeledContent("Ressemblance minimale", value: settings.seriesSimilarity.percentString)
                        Slider(value: $settings.seriesSimilarity, in: 0.75...0.97, step: 0.01)
                    }
                    Stepper("Écart max : \(Int(settings.seriesMaxGap / 60)) min",
                            value: $settings.seriesMaxGap, in: 60...7200, step: 60)
                } header: {
                    Text("Séries")
                } footer: {
                    Text("Baissez la ressemblance pour trouver plus de séries, montez-la pour ne garder que les quasi-doublons.")
                }

                Section("Nettoyage") {
                    Stepper("Grosse vidéo à partir de \(Int(settings.largeVideoMB)) Mo",
                            value: $settings.largeVideoMB, in: 20...2000, step: 20)
                }

                Section {
                    Button("Revoir les albums refusés") { store.restoreDismissedAlbums() }
                    Button("Réanalyser toutes les photos") { confirmReanalyze = true }
                    Button("Effacer l'apprentissage", role: .destructive) { confirmReset = true }
                } header: {
                    Text("Avancé")
                }

                Section("Confidentialité") {
                    Label("Toute l'analyse est faite sur l'iPhone par l'IA d'Apple. Aucune photo ni information ne quitte votre téléphone.", systemImage: "lock.shield")
                        .font(.footnote)
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        store.updateSettings(settings)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
            .onAppear { settings = store.state.settings }
            .confirmationDialog("Effacer tout ce que Pétale a appris ?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Effacer l'apprentissage", role: .destructive) { store.resetLearning() }
            } message: {
                Text("Vos photos ne sont pas touchées. Il faudra refaire des tris pour réactiver les suggestions.")
            }
            .confirmationDialog("Réanalyser toutes les photos ?", isPresented: $confirmReanalyze, titleVisibility: .visible) {
                Button("Réanalyser") { store.reanalyzeEverything() }
            } message: {
                Text("Cela peut prendre quelques minutes. Votre apprentissage est conservé.")
            }
        }
    }
}
