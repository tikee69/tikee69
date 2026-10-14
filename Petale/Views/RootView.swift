import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !store.isLoaded {
                ProgressView()
            } else if store.hasAccess {
                MainTabView()
            } else {
                PermissionView()
            }
        }
        .task { await store.start() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: store.appBecameActive()
            case .background: store.appWentToBackground()
            default: break
            }
        }
        .alert("Oups", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .overlay(alignment: .top) {
            if let toast = store.toast {
                ToastView(text: toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toast) {
                        try? await Task.sleep(for: .seconds(2.5))
                        withAnimation { store.toast = nil }
                    }
            }
        }
        .animation(.spring(duration: 0.35), value: store.toast)
    }
}

struct MainTabView: View {
    @Environment(AppStore.self) private var store
    @State private var selection = AppTab.home

    var body: some View {
        TabView(selection: $selection) {
            Tab("Accueil", systemImage: "house.fill", value: AppTab.home) {
                HomeView(selection: $selection)
            }
            Tab("Trier", systemImage: "rectangle.stack.fill", value: AppTab.swipe) {
                SwipeView()
            }
            .badge(store.basket.count)
            Tab("Séries", systemImage: "square.stack.3d.down.right.fill", value: AppTab.series) {
                SeriesListView()
            }
            .badge(store.insights.series.count)
            Tab("Nettoyer", systemImage: "sparkles", value: AppTab.clean) {
                CleanView()
            }
            Tab("Pour vous", systemImage: "heart.text.square.fill", value: AppTab.forYou) {
                ForYouView(selection: $selection)
            }
            .badge(store.insights.suggestions.count)
        }
    }
}

enum AppTab: Hashable {
    case home, swipe, series, clean, forYou
}

struct ToastView: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            .padding(.top, 8)
    }
}

struct PermissionView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
            VStack(spacing: 8) {
                Text("Bienvenue dans Pétale")
                    .font(.largeTitle.bold())
                Text("Pétale vous aide à faire le tri dans vos photos : doublons, photos ratées, captures d'écran… et apprend de vos choix pour vous faire gagner de la place.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 14) {
                Label("Tout reste sur votre iPhone, rien n'est envoyé sur internet.", systemImage: "lock.shield.fill")
                Label("Rien n'est supprimé sans votre accord.", systemImage: "hand.raised.fill")
                Label("Les photos supprimées restent 30 jours dans « Supprimés récemment ».", systemImage: "arrow.uturn.backward.circle.fill")
            }
            .font(.subheadline)
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Spacer()
            if store.authorization == .denied || store.authorization == .restricted {
                Text("L'accès aux photos a été refusé. Autorisez « Accès complet » dans les Réglages.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Text("Ouvrir les Réglages").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button {
                    Task { await store.requestAccess() }
                } label: {
                    Text("Autoriser l'accès aux photos").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(24)
    }
}
