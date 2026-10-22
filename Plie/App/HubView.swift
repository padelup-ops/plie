import SwiftUI

struct HubView: View {
    @Environment(AppState.self) private var app
    @Environment(StoreManager.self) private var store
    @State private var showSettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                HStack {
                    Spacer()
                    IconButton(symbol: "gearshape.fill", label: "Réglages") {
                        showSettings = true
                    }
                }

                VStack(spacing: 6) {
                    Text("PLIÉ")
                        .font(.plie(84))
                        .foregroundStyle(
                            LinearGradient(colors: [Theme.laser, Theme.gold, Theme.sun],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                    Text("Quatre jeux pensés pour l'iPhone Duo")
                        .font(.plie(18, weight: .bold))
                        .foregroundStyle(.white)
                    if !DuoSupport.apisAvailable {
                        Text("Sur cet iPhone, tu joues au doigt à la place de la charnière.")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.bottom, 4)

                gameCard(title: "RAYON",
                         subtitle: "Plie ton téléphone pour orienter le miroir, fais pivoter les autres, et touche la cible avec le laser.",
                         symbol: "light.beacon.max.fill",
                         color: Theme.laser,
                         badge: "Charnière · Casse-tête",
                         progress: "\(app.rayonSolved.count) / \(RayonLevel.all.count) niveaux") {
                    app.route = .rayonLevels
                }

                gameCard(title: "PLIAGE",
                         subtitle: "La peinture est fraîche : plie la feuille pour la décalquer et reproduire le modèle.",
                         symbol: "paintpalette.fill",
                         color: Theme.paint,
                         badge: "Plis · Casse-tête",
                         progress: "\(app.pliageSolved.count) / \(PliageLevel.all.count) pliages") {
                    app.route = .pliageLevels
                }

                gameCard(title: "LE COFFRE",
                         subtitle: "Ouvre la charnière comme une molette, sens le bon cran, craque la combinaison.",
                         symbol: "lock.rotation",
                         color: Theme.gold,
                         badge: "Charnière · Solo ou duel",
                         progress: "\(app.coffreBest.count) / \(CoffreLevel.count) coffres") {
                    app.route = .coffreLevels
                }

                gameCard(title: "1, 2, 3… SOLEIL !",
                         subtitle: "Le téléphone fait l'arbitre : il voit qui bouge et le renvoie au départ.",
                         symbol: "sun.max.fill",
                         color: Theme.sun,
                         badge: "Caméra · 2 joueurs et +",
                         progress: app.soleilGames == 0 ? "Jamais joué" : "\(app.soleilGames) partie\(app.soleilGames > 1 ? "s" : "")") {
                    app.route = .soleil
                }

                if !store.ownsPass {
                    Button {
                        app.showPass = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 22, weight: .bold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Pass Plié")
                                    .font(.plie(18))
                                Text("Tous les niveaux, pour toujours")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .opacity(0.85)
                            }
                            Spacer()
                            Text(store.pass?.displayPrice ?? "")
                                .font(.plie(17))
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.gold))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(app)
                .environment(store)
        }
    }

    private func gameCard(title: String,
                          subtitle: String,
                          symbol: String,
                          color: Color,
                          badge: String,
                          progress: String,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 64, height: 64)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(color))

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.plie(22))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 6) {
                        Pill(text: badge, color: color.opacity(0.18), textColor: color)
                            .fixedSize()
                        Text(progress)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.muted)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 22)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.card))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(color.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(StoreManager.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Ressenti") {
                    Toggle("Sons", isOn: Binding(get: { app.soundOn }, set: { app.setSound($0) }))
                    Toggle("Vibrations", isOn: Binding(get: { app.hapticsOn }, set: { app.setHaptics($0) }))
                }
                Section("Pass Plié") {
                    if store.ownsPass {
                        Label("Tout est débloqué", systemImage: "checkmark.seal.fill")
                    } else {
                        Button("Voir le Pass") {
                            dismiss()
                            app.showPass = true
                        }
                    }
                    Button("Restaurer mes achats") {
                        Task { await store.restore() }
                    }
                    if let message = store.message {
                        Text(message).foregroundStyle(Theme.muted)
                    }
                }
                Section("iPhone Duo") {
                    Text(DuoSupport.apisAvailable
                         ? "Sur iPhone Duo, RAYON, PLIAGE et LE COFFRE se jouent avec la charnière, et 1, 2, 3… Soleil ! peut afficher le signal sur l'écran extérieur. Sur les autres iPhone, tout se joue au doigt."
                         : "Cet iPhone n'a pas de charnière : RAYON, PLIAGE et LE COFFRE se jouent au doigt.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                }
                Section("Vie privée") {
                    Text("Dans 1, 2, 3… Soleil !, la caméra sert à repérer les mouvements, directement sur le téléphone. Les photos des joueurs pris restent dans l'app le temps de la partie, et ne sont partagées que si tu le choisis.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ink.ignoresSafeArea())
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }
}

struct PassView: View {
    @Environment(StoreManager.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    Spacer()
                    IconButton(symbol: "xmark", label: "Fermer") { dismiss() }
                }
                Image(systemName: "crown.fill")
                    .font(.system(size: 54, weight: .bold))
                    .foregroundStyle(Theme.gold)
                Text("Pass Plié")
                    .font(.plie(40))
                Text("Un seul achat, sans abonnement ni publicité.")
                    .font(.plie(17, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 14) {
                    benefit("light.beacon.max.fill", Theme.laser, "RAYON : \(RayonLevel.all.count - AppState.freeRayonLevels) niveaux de plus", "Miroirs pivotants, labyrinthes et miroirs jumeaux.")
                    benefit("paintpalette.fill", Theme.paint, "PLIAGE : \(PliageLevel.all.count - AppState.freePliageLevels) pliages de plus", "Mélanges de couleurs et origamis en 4 plis.")
                    benefit("lock.rotation", Theme.gold, "LE COFFRE : \(CoffreLevel.count - AppState.freeCoffreLevels) coffres de plus", "Faux crans, crans discrets, et coffres sans chiffres, au toucher seulement.")
                    benefit("sparkles", Theme.sun, "Les prochains jeux et niveaux", "Tout ce qui sortira plus tard est inclus.")
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card))

                if store.ownsPass {
                    Label("Déjà débloqué, merci !", systemImage: "checkmark.seal.fill")
                        .font(.plie(18, weight: .bold))
                        .foregroundStyle(Theme.go)
                } else {
                    Button {
                        Task { await store.buyPass() }
                    } label: {
                        if store.isPurchasing {
                            ProgressView().tint(Theme.ink)
                        } else if let pass = store.pass {
                            Text("Tout débloquer pour \(pass.displayPrice)")
                        } else {
                            Text(store.isLoading ? "Chargement…" : "Indisponible pour le moment")
                        }
                    }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.gold, textColor: Theme.ink, height: 62))
                    .disabled(store.pass == nil || store.isPurchasing)
                }

                Button("Restaurer mes achats") {
                    Task { await store.restore() }
                }
                .buttonStyle(GhostButtonStyle())

                if let message = store.message {
                    Text(message)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(22)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.ink.ignoresSafeArea())
        .foregroundStyle(.white)
        .task {
            if store.pass == nil { await store.load() }
        }
    }

    private func benefit(_ symbol: String, _ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.plie(16, weight: .bold))
                Text(detail)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
