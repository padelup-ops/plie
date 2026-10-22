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
                    IconButton(symbol: "gearshape.fill", label: L("Réglages")) {
                        showSettings = true
                    }
                }

                VStack(spacing: 6) {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        Text(L("PLIÉ"))
                            .font(.plie(88))
                            .foregroundStyle(
                                LinearGradient(colors: [Theme.laser, Theme.paint, Theme.gold, Theme.sun, Theme.laser],
                                               startPoint: UnitPoint(x: -0.5 + (t * 0.08).truncatingRemainder(dividingBy: 1), y: 0),
                                               endPoint: UnitPoint(x: 1.5 + (t * 0.08).truncatingRemainder(dividingBy: 1), y: 1))
                            )
                            .shadow(color: Theme.paint.opacity(0.45), radius: 18)
                            .rotation3DEffect(.degrees(6 * sin(t * 0.8)), axis: (x: 0, y: 1, z: 0))
                    }
                    Text(L("Neuf jeux pensés pour l'iPhone Duo"))
                        .font(.plie(18, weight: .bold))
                        .foregroundStyle(.white)
                    if !DuoSupport.apisAvailable {
                        Text(L("Sur cet iPhone, tu joues au doigt à la place de la charnière."))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.bottom, 4)

                SectionTitle(text: L("Casse-tête"))

                gameCard(title: L("RAYON"),
                         subtitle: L("Plie ton téléphone pour orienter le miroir, fais pivoter les autres, et touche la cible avec le laser."),
                         symbol: "light.beacon.max.fill",
                         color: Theme.laser,
                         badge: L("Charnière · Casse-tête"),
                         progress: L("\(app.rayonSolved.count) / \(RayonLevel.all.count) niveaux")) {
                    app.route = .rayonLevels
                }

                gameCard(title: L("PLIAGE"),
                         subtitle: L("La peinture est fraîche : plie la feuille pour la décalquer et reproduire le modèle."),
                         symbol: "paintpalette.fill",
                         color: Theme.paint,
                         badge: L("Plis · Casse-tête"),
                         progress: L("\(app.pliageSolved.count) / \(PliageLevel.all.count) pliages")) {
                    app.route = .pliageLevels
                }

                gameCard(title: L("BASCULE"),
                         subtitle: L("Le pli règle le tremplin : envoie la bille dans le panier en ramassant les étoiles."),
                         symbol: "arrow.up.right.circle.fill",
                         color: Theme.bascule,
                         badge: L("Charnière · Adresse"),
                         progress: L("\(app.basculeStars.count) / \(BasculeLevel.all.count) niveaux")) {
                    app.route = .basculeLevels
                }

                gameCard(title: L("LE COFFRE"),
                         subtitle: L("Ouvre la charnière comme une molette, sens le bon cran, craque la combinaison."),
                         symbol: "lock.rotation",
                         color: Theme.gold,
                         badge: L("Charnière · Solo ou duel"),
                         progress: L("\(app.coffreBest.count) / \(CoffreLevel.count) coffres")) {
                    app.route = .coffreLevels
                }

                SectionTitle(text: L("Arcade"))

                gameCard(title: L("PANIER"),
                         subtitle: L("Plie ton Duo en L : le panier se dresse devant toi. Un maximum de paniers en 60 secondes."),
                         symbol: "basketball.fill",
                         color: Theme.panier,
                         badge: L("Pli en L · Solo"),
                         progress: app.panierBest == 0 ? L("Pas encore de record") : L("Record : \(app.panierBest) points")) {
                    app.route = .panier
                }

                gameCard(title: L("FLÉCHETTES"),
                         subtitle: L("La cible sur la moitié debout, la fléchette sous ton doigt. Seul ou à deux."),
                         symbol: "scope",
                         color: Theme.darts,
                         badge: L("Pli en L · 1 ou 2 joueurs"),
                         progress: app.flechettesBest == 0 ? L("Pas encore de record") : L("Record : \(app.flechettesBest) points")) {
                    app.route = .flechettes
                }

                gameCard(title: L("AIR HOCKEY"),
                         subtitle: L("Duo ouvert à plat entre vous deux : la charnière devient la ligne médiane."),
                         symbol: "circle.circle.fill",
                         color: Theme.hockeyB,
                         badge: L("À plat · 1 ou 2 joueurs"),
                         progress: L("Premier à 7 buts")) {
                    app.route = .airHockey
                }

                SectionTitle(text: L("En groupe"))

                gameCard(title: L("1, 2, 3… SOLEIL !"),
                         subtitle: L("Le téléphone fait l'arbitre : il voit qui bouge et le renvoie au départ."),
                         symbol: "sun.max.fill",
                         color: Theme.sun,
                         badge: L("Caméra · 2 joueurs et +"),
                         progress: app.soleilGames == 0 ? L("Jamais joué") : L("\(app.soleilGames) partie\(app.soleilGames > 1 ? "s" : "")")) {
                    app.route = .soleil
                }

                SectionTitle(text: L("Concentration"))

                gameCard(title: L("FERME"),
                         subtitle: L("Ferme ton Duo et ta plante pousse sur l'écran extérieur. Rouvre-le trop tôt, elle fane."),
                         symbol: "leaf.fill",
                         color: Theme.ferme,
                         badge: L("Fermé · Concentration"),
                         progress: app.fermeGarden.isEmpty ? L("Jardin vide") : L("\(app.fermeGarden.count) plante\(app.fermeGarden.count > 1 ? "s" : "") dans ton jardin")) {
                    app.route = .ferme
                }

                if !store.ownsPass {
                    Button {
                        app.showPass = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 22, weight: .bold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("Pass Plié"))
                                    .font(.plie(18))
                                Text(L("Tous les niveaux, pour toujours"))
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
        // Le fond lumineux est dessiné par RootView.
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
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(LinearGradient(colors: [color, color.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center))
                    Image(systemName: symbol)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .shadow(color: .white.opacity(0.4), radius: 1, y: 1)
                }
                .frame(width: 66, height: 66)
                .shadow(color: color.opacity(0.55), radius: 12, y: 4)

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
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(LinearGradient(colors: [color.opacity(0.16), Theme.card.opacity(0.55)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [color.opacity(0.6), .white.opacity(0.08)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
        }
        .buttonStyle(PressableStyle())
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(StoreManager.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(L("Ressenti")) {
                    Toggle(L("Musique"), isOn: Binding(get: { app.musicOn }, set: { app.setMusic($0) }))
                    Toggle(L("Sons"), isOn: Binding(get: { app.soundOn }, set: { app.setSound($0) }))
                    Toggle(L("Vibrations"), isOn: Binding(get: { app.hapticsOn }, set: { app.setHaptics($0) }))
                }
                Section(L("Pass Plié")) {
                    if store.ownsPass {
                        Label(L("Tout est débloqué"), systemImage: "checkmark.seal.fill")
                    } else {
                        Button(L("Voir le Pass")) {
                            dismiss()
                            app.showPass = true
                        }
                    }
                    Button(L("Restaurer mes achats")) {
                        Task { await store.restore() }
                    }
                    if let message = store.message {
                        Text(message).foregroundStyle(Theme.muted)
                    }
                }
                Section(L("iPhone Duo")) {
                    Text(DuoSupport.apisAvailable
                         ? L("Sur iPhone Duo, RAYON, PLIAGE, BASCULE et LE COFFRE se jouent avec la charnière ; PANIER et FLÉCHETTES se jouent plié en L, AIR HOCKEY à plat, FERME fermé. Sur les autres iPhone, tout se joue au doigt.")
                         : L("Cet iPhone n'a pas de charnière : RAYON, PLIAGE et LE COFFRE se jouent au doigt."))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                }
                Section("Langue · Language") {
                    Picker("Langue · Language", selection: Binding(get: { Lang.shared.choice }, set: { Lang.shared.choice = $0 })) {
                        Text(verbatim: "Automatique · Automatic").tag(Lang.Choice.auto)
                        Text(verbatim: "Français").tag(Lang.Choice.fr)
                        Text(verbatim: "English").tag(Lang.Choice.en)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section(L("Vie privée")) {
                    Text(L("Dans 1, 2, 3… Soleil !, la caméra sert à repérer les mouvements, directement sur le téléphone. Les photos des joueurs pris restent dans l'app le temps de la partie, et ne sont partagées que si tu le choisis."))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ink.ignoresSafeArea())
            .navigationTitle(L("Réglages"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("OK")) { dismiss() }
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
                    IconButton(symbol: "xmark", label: L("Fermer")) { dismiss() }
                }
                Image(systemName: "crown.fill")
                    .font(.system(size: 54, weight: .bold))
                    .foregroundStyle(Theme.gold)
                Text(L("Pass Plié"))
                    .font(.plie(40))
                Text(L("Un seul achat, sans abonnement ni publicité."))
                    .font(.plie(17, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 14) {
                    benefit("light.beacon.max.fill", Theme.laser, L("RAYON : \(RayonLevel.all.count - AppState.freeRayonLevels) niveaux de plus"), L("Miroirs pivotants, labyrinthes et miroirs jumeaux."))
                    benefit("paintpalette.fill", Theme.paint, L("PLIAGE : \(PliageLevel.all.count - AppState.freePliageLevels) pliages de plus"), L("Mélanges de couleurs et origamis en 4 plis."))
                    benefit("lock.rotation", Theme.gold, L("LE COFFRE : \(CoffreLevel.count - AppState.freeCoffreLevels) coffres de plus"), L("Faux crans, crans discrets, et coffres sans chiffres, au toucher seulement."))
                    benefit("arrow.up.right.circle.fill", Theme.bascule, L("BASCULE : \(BasculeLevel.all.count - AppState.freeBasculeLevels) niveaux de plus"), L("Le vent, puis les ressorts."))
                    benefit("leaf.fill", Theme.ferme, L("FERME : toutes les plantes"), L("Tulipe, lavande, bonsaï, cerisier, rose, et les séances de 45 à 90 minutes."))
                    benefit("sparkles", Theme.sun, L("Les prochains jeux et niveaux"), L("Tout ce qui sortira plus tard est inclus."))
                }
                .padding(18)
                .background(GlassPanel(cornerRadius: 22))

                if store.ownsPass {
                    Label(L("Déjà débloqué, merci !"), systemImage: "checkmark.seal.fill")
                        .font(.plie(18, weight: .bold))
                        .foregroundStyle(Theme.go)
                } else {
                    Button {
                        Task { await store.buyPass() }
                    } label: {
                        if store.isPurchasing {
                            ProgressView().tint(Theme.ink)
                        } else if let pass = store.pass {
                            Text(L("Tout débloquer pour \(pass.displayPrice)"))
                        } else {
                            Text(store.isLoading ? L("Chargement…") : L("Indisponible pour le moment"))
                        }
                    }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.gold, textColor: Theme.ink, height: 62))
                    .disabled(store.pass == nil || store.isPurchasing)
                }

                Button(L("Restaurer mes achats")) {
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

/// Bouton qui s'enfonce légèrement quand on appuie.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? 0.05 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
