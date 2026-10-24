import SwiftUI

// MARK: - Les jeux d'Origamo
//
// Une seule liste décrit chaque jeu : son nom, ses couleurs, comment tenir le Duo,
// et le mode d'emploi affiché à la première partie (et avec le bouton « ? »).

enum Posture {
    /// On plie et déplie la charnière pour jouer.
    case fold
    /// Duo plié à 90°, posé sur la table : une moitié debout, une moitié à plat.
    case lShape
    /// Duo ouvert à plat sur la table.
    case flat
    /// On passe de l'écran intérieur à l'écran extérieur, et retour.
    case openClose
    /// Duo fermé : l'écran extérieur.
    case closed
    /// Debout au bout de la pièce, face aux joueurs.
    case standing

    var label: String {
        switch self {
        case .fold: return L("Se joue en pliant")
        case .lShape: return L("Plié en L")
        case .flat: return L("À plat")
        case .openClose: return L("Ouvert puis fermé")
        case .closed: return L("Fermé")
        case .standing: return L("Debout, face aux joueurs")
        }
    }
}

enum HubFilter: String, CaseIterable, Identifiable {
    case all, solo, duo, family, kids

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return L("Tous")
        case .solo: return L("Seul")
        case .duo: return L("À deux")
        case .family: return L("En famille")
        case .kids: return L("Enfants")
        }
    }

    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .solo: return "person.fill"
        case .duo: return "person.2.fill"
        case .family: return "person.3.fill"
        case .kids: return "graduationcap.fill"
        }
    }
}

struct HowToStep: Identifiable {
    let id = UUID()
    let symbol: String
    let text: String
}

enum GameID: String, CaseIterable, Identifiable {
    case rayon, bascule, coffre, filet, airHockey, billard, chess, draughts, luciole, ecole, piano, soleil, ferme

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rayon: return L("RAYON")
        case .bascule: return L("BASCULE")
        case .coffre: return L("LE COFFRE")
        case .filet: return L("FILET")
        case .airHockey: return L("AIR HOCKEY")
        case .billard: return L("BILLARD")
        case .chess: return L("ÉCHECS")
        case .draughts: return L("DAMES")
        case .luciole: return L("LUCIOLE")
        case .ecole: return L("ÉCOLE")
        case .piano: return L("PIANO")
        case .soleil: return L("1, 2, 3… SOLEIL !")
        case .ferme: return L("FERME")
        }
    }

    /// Une phrase courte pour la vignette de l'accueil.
    var tagline: String {
        switch self {
        case .rayon: return L("Plie pour viser le laser")
        case .bascule: return L("Le pli règle le tremplin")
        case .coffre: return L("La charnière est une molette")
        case .filet: return L("Ping-pong, la charnière est le filet")
        case .airHockey: return L("Le palet fuse d'un bout à l'autre")
        case .billard: return L("Une vraie table sur tout l'écran")
        case .chess: return L("Face à face, ou contre l'ordi")
        case .draughts: return L("100 cases, rafles et dames volantes")
        case .luciole: return L("Ferme le Duo pour entrer dans la grotte")
        case .ecole: return L("Le tableau en haut, l'ardoise en bas")
        case .piano: return L("Le clavier à plat, la partition debout")
        case .soleil: return L("Le téléphone fait l'arbitre")
        case .ferme: return L("Ferme le Duo, ta plante pousse")
        }
    }

    var color: Color {
        switch self {
        case .rayon: return Color(hex: 0x3DE0FF)
        case .bascule: return Color(hex: 0x8BDB4F)
        case .coffre: return Color(hex: 0xFFC53D)
        case .filet: return Color(hex: 0x5B8CFF)
        case .airHockey: return Color(hex: 0xFF5C8A)
        case .billard: return Color(hex: 0x2FD08C)
        case .chess: return Color(hex: 0xE9B872)
        case .draughts: return Color(hex: 0xFF8A5C)
        case .luciole: return Color(hex: 0xC6F25A)
        case .ecole: return Color(hex: 0xFFD84D)
        case .piano: return Color(hex: 0xC59BFF)
        case .soleil: return Color(hex: 0xFF8A2F)
        case .ferme: return Color(hex: 0x5FD3A0)
        }
    }

    var symbol: String {
        switch self {
        case .rayon: return "light.beacon.max.fill"
        case .bascule: return "arrow.up.right.circle.fill"
        case .coffre: return "lock.rotation"
        case .filet: return "figure.table.tennis"
        case .airHockey: return "circle.circle.fill"
        case .billard: return "circle.grid.cross.fill"
        case .chess: return "crown.fill"
        case .draughts: return "circle.grid.2x2.fill"
        case .luciole: return "sparkles"
        case .ecole: return "pencil.and.scribble"
        case .piano: return "pianokeys"
        case .soleil: return "sun.max.fill"
        case .ferme: return "leaf.fill"
        }
    }

    var posture: Posture {
        switch self {
        case .rayon, .bascule, .coffre: return .fold
        case .filet, .ecole, .piano: return .lShape
        case .airHockey, .billard, .chess, .draughts: return .flat
        case .luciole: return .openClose
        case .soleil: return .standing
        case .ferme: return .closed
        }
    }

    var players: String {
        switch self {
        case .rayon, .bascule, .luciole, .piano, .ferme: return L("Seul")
        case .coffre: return L("Seul ou à deux")
        case .filet: return L("Contre l'ordi")
        case .airHockey, .billard, .chess, .draughts: return L("1 ou 2 joueurs")
        case .ecole: return L("Dès 4 ans")
        case .soleil: return L("2 joueurs et plus")
        }
    }

    var filters: Set<HubFilter> {
        switch self {
        case .rayon, .bascule, .luciole: return [.solo, .kids]
        case .coffre: return [.solo, .duo]
        case .filet: return [.solo]
        case .airHockey, .billard: return [.solo, .duo, .family]
        case .chess, .draughts: return [.solo, .duo]
        case .ecole: return [.kids, .solo]
        case .piano: return [.solo, .kids]
        case .soleil: return [.family, .kids]
        case .ferme: return [.solo]
        }
    }

    var route: Route {
        switch self {
        case .rayon: return .rayonLevels
        case .bascule: return .basculeLevels
        case .coffre: return .coffreLevels
        case .filet: return .filet
        case .airHockey: return .airHockey
        case .billard: return .billard
        case .chess: return .chess
        case .draughts: return .draughts
        case .luciole: return .luciole
        case .ecole: return .ecole
        case .piano: return .piano
        case .soleil: return .soleil
        case .ferme: return .ferme
        }
    }

    /// Le jeu qui correspond à un écran de l'app (pour le mode d'emploi).
    static func of(_ route: Route) -> GameID? {
        switch route {
        case .hub: return nil
        case .rayonLevels, .rayon: return .rayon
        case .basculeLevels, .bascule: return .bascule
        case .coffreLevels, .coffre, .coffreDuel: return .coffre
        case .filet: return .filet
        case .airHockey: return .airHockey
        case .billard: return .billard
        case .chess: return .chess
        case .draughts: return .draughts
        case .luciole: return .luciole
        case .ecole: return .ecole
        case .piano: return .piano
        case .soleil: return .soleil
        case .ferme: return .ferme
        }
    }

    /// Mode d'emploi, étape par étape. `duo` : l'appareil a une charnière.
    func howTo(duo: Bool) -> [HowToStep] {
        switch self {
        case .rayon:
            return [
                HowToStep(symbol: "target", text: L("But : envoyer le laser sur la cible ronde.")),
                duo ? HowToStep(symbol: "book.fill", text: L("Ouvre ton Duo comme un livre. Plie ou déplie doucement : le miroir bleu tourne avec la charnière."))
                    : HowToStep(symbol: "hand.draw.fill", text: L("Glisse ton doigt sur le plateau : le miroir bleu tourne.")),
                HowToStep(symbol: "hand.tap.fill", text: L("Les miroirs ronds tournent de 45° quand tu les touches.")),
                HowToStep(symbol: "checkmark.circle.fill", text: L("Garde le laser sur la cible un instant : niveau réussi !"))
            ]
        case .bascule:
            return [
                HowToStep(symbol: "basket.fill", text: L("But : faire tomber la bille dans le panier en ramassant les étoiles.")),
                duo ? HowToStep(symbol: "book.fill", text: L("Plie ou déplie ton Duo : plus tu le fermes, plus le tremplin se relève."))
                    : HowToStep(symbol: "hand.draw.fill", text: L("Glisse ton doigt vers le haut ou le bas pour régler le tremplin.")),
                HowToStep(symbol: "hand.tap.fill", text: L("Touche « Lâcher la bille » pour la lancer.")),
                HowToStep(symbol: "star.fill", text: L("Ramasse les 3 étoiles en route pour un sans-faute."))
            ]
        case .coffre:
            return [
                HowToStep(symbol: "lock.fill", text: L("But : trouver les chiffres de la combinaison pour ouvrir le coffre.")),
                duo ? HowToStep(symbol: "dial.medium.fill", text: L("Ouvre et ferme ton Duo très lentement : la charnière est la molette. Chaque cran fait un petit clic."))
                    : HowToStep(symbol: "dial.medium.fill", text: L("Tourne la molette du doigt, lentement. Chaque cran fait un petit clic.")),
                HowToStep(symbol: "ear.fill", text: L("Un « clonk » plus fort ? C'est le bon chiffre : ne bouge plus pendant une seconde.")),
                HowToStep(symbol: "person.2.fill", text: L("En duel, chacun cache un code à l'autre. Le plus rapide gagne."))
            ]
        case .filet:
            return [
                HowToStep(symbol: "figure.table.tennis", text: L("But : marquer 7 points avant l'ordinateur.")),
                duo ? HowToStep(symbol: "laptopcomputer", text: L("Plie ton Duo en L et pose-le sur la table : la charnière devient le filet."))
                    : HowToStep(symbol: "iphone", text: L("Tiens ton téléphone droit : la ligne du milieu est le filet.")),
                HowToStep(symbol: "hand.point.up.left.fill", text: L("Ta raquette suit ton doigt sur la moitié du bas. Touche l'écran pour servir.")),
                HowToStep(symbol: "arrow.up.forward", text: L("Pousse vers le filet pour frapper fort, de côté pour viser un coin. L'ordinateur renvoie tout seul."))
            ]
        case .airHockey:
            return [
                HowToStep(symbol: "rotate.right.fill", text: L("Tourne le téléphone à l'horizontale et pose-le ouvert à plat.")),
                HowToStep(symbol: "hand.draw.fill", text: L("Glisse ton maillet sur ta moitié pour frapper le palet. La charnière est la ligne du milieu.")),
                HowToStep(symbol: "person.2.fill", text: L("Seul contre l'ordinateur, ou à deux : un joueur à chaque bout.")),
                HowToStep(symbol: "flag.checkered", text: L("Le premier à 7 buts gagne."))
            ]
        case .billard:
            return [
                HowToStep(symbol: "rotate.right.fill", text: L("Tourne le téléphone à l'horizontale et pose-le ouvert à plat : la table prend tout l'écran.")),
                HowToStep(symbol: "hand.draw.fill", text: L("Pose le doigt sur la table et tire vers l'arrière, comme une queue de billard. Plus tu tires, plus tu tapes fort.")),
                HowToStep(symbol: "hand.raised.fill", text: L("Lâche pour tirer. La ligne pointillée montre où part la bille blanche.")),
                HowToStep(symbol: "circle.grid.cross.fill", text: L("Rentre toutes tes billes (pleines ou rayées), puis la noire. À deux, on joue chacun son tour."))
            ]
        case .chess:
            return [
                duo ? HowToStep(symbol: "rectangle.split.2x1.fill", text: L("Déplie ton Duo à plat entre vous deux : chacun voit ses pièces à l'endroit."))
                    : HowToStep(symbol: "iphone", text: L("Pose le téléphone à plat entre vous deux, ou joue contre l'ordinateur.")),
                HowToStep(symbol: "hand.tap.fill", text: L("Touche une pièce pour voir ses coups, puis touche la case d'arrivée.")),
                HowToStep(symbol: "timer", text: L("Avec la pendule, replie un peu le Duo pour la mettre en pause.")),
                HowToStep(symbol: "crown.fill", text: L("Toutes les règles sont là : roque, prise en passant, promotion, pat et nulles."))
            ]
        case .draughts:
            return [
                duo ? HowToStep(symbol: "rectangle.split.2x1.fill", text: L("Déplie ton Duo à plat entre vous deux : chacun voit ses pions à l'endroit."))
                    : HowToStep(symbol: "iphone", text: L("Pose le téléphone à plat entre vous deux, ou joue contre l'ordinateur.")),
                HowToStep(symbol: "hand.tap.fill", text: L("Touche un pion, puis sa case d'arrivée.")),
                HowToStep(symbol: "exclamationmark.circle.fill", text: L("Prendre est obligatoire, et il faut prendre le plus de pièces possible.")),
                HowToStep(symbol: "crown.fill", text: L("Un pion qui arrive au bout devient une dame : elle vole sur toute la diagonale."))
            ]
        case .luciole:
            return [
                HowToStep(symbol: "sparkles", text: L("But : guider la luciole jusqu'au bout du voyage en ramassant la lumière.")),
                HowToStep(symbol: "hand.point.up.left.fill", text: L("Dans la prairie, Duo ouvert : la luciole suit ton doigt. Ramasse les lucioles amies.")),
                duo ? HowToStep(symbol: "rectangle.portrait.on.rectangle.portrait", text: L("Devant la grotte, ferme ton Duo : le voyage continue sur l'écran extérieur. Touche à gauche ou à droite pour éviter les rochers."))
                    : HowToStep(symbol: "rectangle.portrait.on.rectangle.portrait", text: L("Devant la grotte, touche « Entrer » : touche à gauche ou à droite pour éviter les rochers.")),
                duo ? HowToStep(symbol: "book.fill", text: L("À la sortie de la grotte, rouvre ton Duo pour retrouver la prairie."))
                    : HowToStep(symbol: "book.fill", text: L("À la sortie de la grotte, touche « Sortir » pour retrouver la prairie."))
            ]
        case .ecole:
            return [
                duo ? HowToStep(symbol: "laptopcomputer", text: L("Plie le Duo en L et pose-le sur la table : en haut le tableau, en bas l'ardoise."))
                    : HowToStep(symbol: "iphone", text: L("La question s'affiche en haut, les réponses en bas.")),
                HowToStep(symbol: "speaker.wave.2.fill", text: L("La maîtresse lit la question à voix haute. Touche le haut-parleur pour l'entendre encore.")),
                HowToStep(symbol: "hand.draw.fill", text: L("Réponds en touchant un bouton, ou écris le nombre à la craie avec ton doigt sur l'ardoise, puis touche « Valider ».")),
                HowToStep(symbol: "star.fill", text: L("Chaque bonne réponse colle une étoile au tableau. 10 questions par leçon."))
            ]
        case .piano:
            return [
                duo ? HowToStep(symbol: "laptopcomputer", text: L("Plie le Duo en L comme un pupitre : le clavier à plat, la partition debout."))
                    : HowToStep(symbol: "iphone", text: L("La partition en haut, le clavier en bas.")),
                HowToStep(symbol: "music.note.list", text: L("Choisis un morceau. En mode « Apprendre », la touche à jouer clignote.")),
                HowToStep(symbol: "hand.tap.fill", text: L("Joue avec plusieurs doigts à la fois. Les flèches changent d'octave.")),
                HowToStep(symbol: "ear.fill", text: L("« Écouter » joue le morceau pour toi, « Libre » te laisse improviser."))
            ]
        case .soleil:
            return [
                duo ? HowToStep(symbol: "laptopcomputer", text: L("Ouvre le Duo en L et pose-le au bout de la pièce, l'écran intérieur face aux joueurs."))
                    : HowToStep(symbol: "iphone", text: L("Pose le téléphone debout au bout de la pièce, l'écran face aux joueurs.")),
                HowToStep(symbol: "figure.walk", text: L("Écran vert, AVANCEZ : on avance vers le téléphone.")),
                HowToStep(symbol: "hand.raised.fill", text: L("La voix dit « soleil », l'écran passe au rouge : on se fige ! Qui bouge est pris en photo et retourne au départ.")),
                HowToStep(symbol: "trophy.fill", text: L("Le premier qui arrive touche « Touché ! » et gagne."))
            ]
        case .ferme:
            return [
                HowToStep(symbol: "leaf.fill", text: L("Choisis une plante et une durée, puis touche « Planter ».")),
                duo ? HowToStep(symbol: "rectangle.portrait.on.rectangle.portrait", text: L("Ferme ton Duo : la plante pousse sur l'écran extérieur pendant que tu te concentres."))
                    : HowToStep(symbol: "iphone", text: L("Pose ton téléphone et ne quitte pas Origamo.")),
                HowToStep(symbol: "exclamationmark.triangle.fill", text: L("Rouvert trop tôt ? Tu as 10 secondes pour refermer, sinon la plante fane.")),
                HowToStep(symbol: "tree.fill", text: L("Fais fleurir les 8 plantes : on plante un vrai arbre pour toi."))
            ]
        }
    }
}

// MARK: - Dessin de la position du Duo

/// Petit dessin du Duo vu de côté, dans la position du jeu.
struct PostureIcon: View {
    let posture: Posture
    var color: Color = .white
    var lineWidth: CGFloat = 3

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let stroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            let shade = GraphicsContext.Shading.color(color)
            var p = Path()
            switch posture {
            case .flat:
                p.move(to: CGPoint(x: w * 0.08, y: h * 0.7))
                p.addLine(to: CGPoint(x: w * 0.92, y: h * 0.7))
                context.stroke(p, with: shade, style: stroke)
                context.fill(Path(ellipseIn: CGRect(x: w * 0.47, y: h * 0.62, width: w * 0.06, height: w * 0.06)), with: shade)
            case .lShape, .standing:
                p.move(to: CGPoint(x: w * 0.2, y: h * 0.15))
                p.addLine(to: CGPoint(x: w * 0.2, y: h * 0.78))
                p.addLine(to: CGPoint(x: w * 0.85, y: h * 0.78))
                context.stroke(p, with: shade, style: stroke)
                if posture == .standing {
                    // Les joueurs, en face
                    for k in 0..<2 {
                        let x = w * (0.62 + 0.18 * CGFloat(k))
                        context.fill(Path(ellipseIn: CGRect(x: x - w * 0.05, y: h * 0.18, width: w * 0.1, height: w * 0.1)), with: shade)
                        var body = Path()
                        body.move(to: CGPoint(x: x, y: h * 0.3))
                        body.addLine(to: CGPoint(x: x, y: h * 0.55))
                        context.stroke(body, with: shade, style: stroke)
                    }
                }
            case .fold:
                p.move(to: CGPoint(x: w * 0.12, y: h * 0.3))
                p.addLine(to: CGPoint(x: w * 0.5, y: h * 0.8))
                p.addLine(to: CGPoint(x: w * 0.88, y: h * 0.3))
                context.stroke(p, with: shade, style: stroke)
                var arc = Path()
                arc.addArc(center: CGPoint(x: w * 0.5, y: h * 0.8), radius: w * 0.3,
                           startAngle: .degrees(-150), endAngle: .degrees(-30), clockwise: false)
                context.stroke(arc, with: .color(color.opacity(0.6)), style: StrokeStyle(lineWidth: lineWidth * 0.6, lineCap: .round, dash: [2, 4]))
            case .closed:
                for k in 0..<2 {
                    var s = Path()
                    let y = h * (0.52 + 0.14 * CGFloat(k))
                    s.move(to: CGPoint(x: w * 0.15, y: y))
                    s.addLine(to: CGPoint(x: w * 0.85, y: y))
                    context.stroke(s, with: shade, style: stroke)
                }
                var hinge = Path()
                hinge.addArc(center: CGPoint(x: w * 0.15, y: h * 0.59), radius: h * 0.07, startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
                context.stroke(hinge, with: shade, style: stroke)
            case .openClose:
                p.move(to: CGPoint(x: w * 0.08, y: h * 0.72))
                p.addLine(to: CGPoint(x: w * 0.42, y: h * 0.72))
                context.stroke(p, with: shade, style: stroke)
                var q = Path()
                q.move(to: CGPoint(x: w * 0.6, y: h * 0.66))
                q.addLine(to: CGPoint(x: w * 0.92, y: h * 0.66))
                q.move(to: CGPoint(x: w * 0.6, y: h * 0.78))
                q.addLine(to: CGPoint(x: w * 0.92, y: h * 0.78))
                context.stroke(q, with: shade, style: stroke)
                var arrow = Path()
                arrow.move(to: CGPoint(x: w * 0.42, y: h * 0.38))
                arrow.addQuadCurve(to: CGPoint(x: w * 0.62, y: h * 0.38), control: CGPoint(x: w * 0.52, y: h * 0.18))
                arrow.move(to: CGPoint(x: w * 0.56, y: h * 0.3))
                arrow.addLine(to: CGPoint(x: w * 0.62, y: h * 0.38))
                arrow.addLine(to: CGPoint(x: w * 0.54, y: h * 0.42))
                context.stroke(arrow, with: .color(color.opacity(0.8)), style: StrokeStyle(lineWidth: lineWidth * 0.7, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityLabel(posture.label)
    }
}

// MARK: - Mode d'emploi

struct HowToSheet: View {
    let game: GameID
    @Environment(\.dismiss) private var dismiss
    @State private var hingePresent = DuoSupport.apisAvailable

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Spacer()
                    IconButton(symbol: "xmark", label: L("Fermer")) { dismiss() }
                }
                HStack(spacing: 16) {
                    ZStack {
                        FoldedPaper(color: game.color, cornerRadius: 22)
                        PostureIcon(posture: game.posture, color: Theme.ink, lineWidth: 4)
                            .padding(14)
                    }
                    .frame(width: 96, height: 96)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Comment jouer"))
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(game.color)
                        Text(game.title)
                            .font(.system(.largeTitle, design: .rounded, weight: .black))
                            .minimumScaleFactor(0.6)
                            .lineLimit(2)
                        Text("\(game.posture.label) · \(game.players)")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(game.howTo(duo: hingePresent).enumerated()), id: \.element.id) { item in
                        HStack(alignment: .top, spacing: 14) {
                            ZStack {
                                Circle().fill(game.color)
                                Text("\(item.offset + 1)")
                                    .font(.system(.headline, design: .rounded, weight: .black))
                                    .foregroundStyle(Theme.ink)
                            }
                            .frame(width: 34, height: 34)
                            .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 6) {
                                Image(systemName: item.element.symbol)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(game.color)
                                    .accessibilityHidden(true)
                                Text(item.element.text)
                                    .font(.system(.body, design: .rounded, weight: .medium))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.07)))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(L("Étape \(item.offset + 1) : \(item.element.text)"))
                    }
                }

                Button {
                    dismiss()
                } label: {
                    Label(L("C'est parti !"), systemImage: "play.fill")
                }
                .buttonStyle(ChunkyButtonStyle(color: game.color, textColor: Theme.ink, height: 60))
            }
            .padding(22)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(.white)
        .background(Theme.ink.ignoresSafeArea())
        .onHingeAngle { if $0 != nil { hingePresent = true } }
        .presentationDragIndicator(.visible)
    }
}

/// Bouton « ? » qui ouvre le mode d'emploi du jeu.
struct HowToButton: View {
    let game: GameID
    @State private var open = false

    var body: some View {
        IconButton(symbol: "questionmark", label: L("Comment jouer")) { open = true }
            .sheet(isPresented: $open) { HowToSheet(game: game) }
    }
}

/// Feuille de papier pliée en deux : la moitié haute un peu plus claire, avec un pli en diagonale.
struct FoldedPaper: View {
    let color: Color
    var cornerRadius: CGFloat = 26

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(color)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(LinearGradient(stops: [
                    .init(color: .white.opacity(0.32), location: 0),
                    .init(color: .white.opacity(0.10), location: 0.499),
                    .init(color: .black.opacity(0.10), location: 0.501),
                    .init(color: .black.opacity(0.22), location: 1)
                ], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }
}
