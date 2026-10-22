import SwiftUI
import Combine

// MARK: - Choix du coffre

struct CoffreLevelsView: View {
    @Environment(AppState.self) private var app
    @Environment(StoreManager.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            GameHeader(title: "LE COFFRE",
                       subtitle: "\(app.coffreBest.count) / \(CoffreLevel.count) coffres ouverts",
                       onBack: { app.route = .hub }) {
                EmptyView()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ScrollView {
                VStack(spacing: 18) {
                    Text(DuoSupport.apisAvailable
                         ? "Ouvre et ferme ton iPhone Duo lentement, comme la molette d'un coffre. Un « clonk » plus fort ? Reste immobile une seconde pour essayer ce chiffre."
                         : "Tourne la molette du doigt, lentement. Un « clonk » plus fort ? Reste immobile une seconde pour essayer ce chiffre.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        app.route = .coffreDuel
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 20, weight: .bold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Duel à deux")
                                    .font(.plie(18))
                                Text("Chacun crée un code, le plus rapide à craquer celui de l'autre gagne")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .opacity(0.8)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.gold))
                    }
                    .buttonStyle(.plain)

                    SectionTitle(text: "Les coffres")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                        ForEach(1...CoffreLevel.count, id: \.self) { number in
                            levelButton(number)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func levelButton(_ number: Int) -> some View {
        let opened = app.coffreBest[number] != nil
        let needsPass = app.coffreNeedsPass(number, hasPass: store.ownsPass)
        let unlocked = app.coffreIsUnlocked(number, hasPass: store.ownsPass)

        return Button {
            if needsPass {
                app.showPass = true
            } else if unlocked {
                app.route = .coffre(number)
            }
        } label: {
            VStack(spacing: 6) {
                if unlocked {
                    Text("\(number)")
                        .font(.plie(24))
                        .foregroundStyle(.white)
                    StarsView(count: app.coffreStars[number] ?? 0, size: 11)
                } else {
                    Image(systemName: needsPass ? "crown.fill" : "lock.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(needsPass ? Theme.gold : Theme.muted)
                    Text("\(number)")
                        .font(.plie(13, weight: .bold))
                        .foregroundStyle(Theme.muted)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 78)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(opened ? Theme.cardHigh : Theme.card))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(opened ? Theme.gold.opacity(0.6) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Coffre \(number)\(opened ? ", ouvert" : "")\(unlocked ? "" : ", verrouillé")")
    }
}

// MARK: - Partie solo

struct CoffrePlayView: View {
    let number: Int

    @Environment(AppState.self) private var app
    @Environment(StoreManager.self) private var store
    @State private var session: CoffreSession
    @State private var usesHinge = false
    @State private var recorded = false
    @State private var stars = 0

    private let ticker = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    init(number: Int) {
        self.number = number
        _session = State(initialValue: CoffreSession(level: CoffreLevel.make(number)))
    }

    var body: some View {
        VStack(spacing: 14) {
            GameHeader(title: "Coffre n° \(number)",
                       subtitle: session.level.features.joined(separator: " · "),
                       onBack: { app.route = .coffreLevels }) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatSeconds(session.elapsed))
                        .font(.plie(17, weight: .bold))
                        .monospacedDigit()
                    if session.mistakes > 0 {
                        Text("\(session.mistakes) erreur\(session.mistakes > 1 ? "s" : "")")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.coral)
                    }
                }
            }

            CombinationSlots(total: session.level.digits, found: session.found, current: session.found.count, opened: session.opened)

            Spacer(minLength: 0)

            CoffreDial(session: session, usesHinge: usesHinge)
                .frame(maxWidth: 420)

            Spacer(minLength: 0)

            CoffreHint(usesHinge: usesHinge)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onHingeAngle { degrees in
            // Duo fermé (ou pas de charnière) : on tourne la molette au doigt.
            guard let degrees, HingeMapping.isOpen(degrees) else {
                usesHinge = false
                return
            }
            usesHinge = true
            session.setFraction(HingeMapping.fraction(fromDegrees: degrees))
        }
        .onReceive(ticker) { _ in
            session.tick(dt: 1.0 / 60.0)
            if session.opened && !recorded {
                recorded = true
                stars = session.level.stars(time: session.elapsed, mistakes: session.mistakes)
                app.recordCoffre(number, time: session.elapsed, stars: stars)
            }
        }
        .onAppear { Haptics.prepare() }
        .overlay {
            if session.opened {
                openedOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeOut(duration: 0.3), value: session.opened)
    }

    private var openedOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(Theme.gold)
                Text("Coffre ouvert !")
                    .font(.plie(34))
                StarsView(count: stars, size: 28)
                Text("\(formatSeconds(session.elapsed)) · \(session.mistakes) erreur\(session.mistakes > 1 ? "s" : "")")
                    .font(.plie(17, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                if stars < 3 {
                    Text("3 étoiles : sans erreur et en moins de \(Int(session.level.par)) s.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                if number < CoffreLevel.count {
                    if app.coffreNeedsPass(number + 1, hasPass: store.ownsPass) {
                        Text("20 coffres plus vicieux t'attendent avec le Pass Plié.")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                        Button("Débloquer la suite") { app.showPass = true }
                            .buttonStyle(ChunkyButtonStyle(color: Theme.gold, textColor: Theme.ink))
                    } else {
                        Button("Coffre suivant") { app.route = .coffre(number + 1) }
                            .buttonStyle(ChunkyButtonStyle(color: Theme.gold, textColor: Theme.ink))
                    }
                } else {
                    Text("Tu as ouvert tous les coffres. Respect.")
                        .font(.plie(17, weight: .bold))
                }
                HStack(spacing: 10) {
                    Button("Rejouer") { app.route = .coffreLevels; DispatchQueue.main.async { app.route = .coffre(number) } }
                        .buttonStyle(GhostButtonStyle())
                    Button("Les coffres") { app.route = .coffreLevels }
                        .buttonStyle(GhostButtonStyle())
                }
            }
            .foregroundStyle(.white)
            .padding(24)
            .frame(maxWidth: 420)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Theme.ink))
            .padding(24)
        }
    }
}

// MARK: - Éléments du coffre

struct CombinationSlots: View {
    let total: Int
    let found: [Int]
    let current: Int
    let opened: Bool
    var showDigits = true

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<total, id: \.self) { index in
                let isFound = index < found.count
                let isCurrent = index == current && !opened
                Text(isFound ? (showDigits ? String(format: "%02d", found[index]) : "✓") : (isCurrent ? "?" : "•"))
                    .font(.plie(26))
                    .monospacedDigit()
                    .foregroundStyle(isFound ? Theme.ink : .white)
                    .frame(width: 62, height: 62)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(isFound ? Theme.gold : Theme.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(isCurrent ? Theme.gold : Color.clear, lineWidth: 2)
                    )
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: found.count)
    }
}

struct CoffreHint: View {
    let usesHinge: Bool
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: usesHinge ? "rectangle.portrait.on.rectangle.portrait" : "hand.draw.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.gold)
                Text(usesHinge
                     ? "Ouvre et ferme lentement. Clonk plus fort ? Ne bouge plus."
                     : "Tourne la molette lentement. Clonk plus fort ? Ne bouge plus.")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
            }
            if !app.soundOn && !app.hapticsOn {
                Text("Active le son ou les vibrations dans les réglages : sans eux, impossible de sentir les crans.")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.coral)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
    }
}

/// La molette. Au doigt, on la fait tourner ; sur iPhone Duo, elle suit la charnière.
struct CoffreDial: View {
    let session: CoffreSession
    let usesHinge: Bool
    var hideNumbersOverride: Bool?

    @State private var lastAngle: Double?
    @State private var shake: CGFloat = 0

    private var hideNumbers: Bool { hideNumbersOverride ?? session.level.hideNumbers }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let positions = session.level.positions
            let step = 360.0 / Double(positions)

            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0x3A3F63), Color(hex: 0x1B1E36)],
                                         center: .center, startRadius: 0, endRadius: side / 2))
                Circle()
                    .strokeBorder(Theme.gold.opacity(0.5), lineWidth: side * 0.015)

                // Graduations et chiffres, qui tournent avec la molette.
                ZStack {
                    ForEach(0..<positions, id: \.self) { index in
                        VStack(spacing: side * 0.012) {
                            Capsule()
                                .fill(index % 5 == 0 ? Color.white : Color.white.opacity(0.45))
                                .frame(width: side * 0.012, height: side * (index % 5 == 0 ? 0.06 : 0.035))
                            if !hideNumbers {
                                Text("\(index)")
                                    .font(.system(size: side * 0.045, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .rotationEffect(.degrees(-Double(index) * step + session.value * step))
                            }
                            Spacer()
                        }
                        .frame(width: side * 0.9, height: side * 0.9)
                        .rotationEffect(.degrees(Double(index) * step))
                    }
                }
                .rotationEffect(.degrees(-session.value * step))

                // Poignée centrale avec l'anneau de maintien.
                Circle()
                    .fill(Color(hex: 0x14172B))
                    .frame(width: side * 0.42, height: side * 0.42)
                    .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
                Circle()
                    .trim(from: 0, to: session.holdProgress)
                    .stroke(Theme.gold, style: StrokeStyle(lineWidth: side * 0.025, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: side * 0.36, height: side * 0.36)
                VStack(spacing: 2) {
                    Text(hideNumbers ? "?" : String(format: "%02d", session.notch))
                        .font(.plie(side * 0.11))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text(session.holdProgress > 0.05 ? "on essaie…" : " ")
                        .font(.system(size: side * 0.035, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.muted)
                }

                // Repère fixe en haut.
                Triangle()
                    .fill(Theme.coral)
                    .frame(width: side * 0.07, height: side * 0.06)
                    .rotationEffect(.degrees(180))
                    .offset(y: -side * 0.5 + side * 0.01)
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            .offset(x: shake)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        let angle = atan2(Double(value.location.y - center.y), Double(value.location.x - center.x)) * 180 / .pi
                        if let previous = lastAngle {
                            var delta = angle - previous
                            if delta > 180 { delta -= 360 }
                            if delta < -180 { delta += 360 }
                            session.nudge(by: delta / step)
                        }
                        lastAngle = angle
                    }
                    .onEnded { _ in lastAngle = nil }
            )
            .allowsHitTesting(!usesHinge)
        }
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: session.eventCount) { _, _ in
            if session.event == .wrong {
                withAnimation(.easeInOut(duration: 0.06).repeatCount(5, autoreverses: true)) { shake = 10 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { shake = 0 }
            }
        }
        .accessibilityLabel("Molette du coffre, position \(session.notch)")
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Duel

struct CoffreDuelView: View {
    enum Phase: Equatable {
        case intro
        case setting(player: Int)
        case handover(cracker: Int)
        case cracking(player: Int)
        case roundResult(player: Int, time: Double)
        case final
    }

    @Environment(AppState.self) private var app
    @State private var phase: Phase = .intro
    @State private var dialValue: Double = 10
    @State private var chosen: [Int] = []
    @State private var codes: [Int: [Int]] = [:]
    @State private var times: [Int: Double] = [:]
    @State private var session: CoffreSession?
    @State private var usesHinge = false
    @State private var lastAngle: Double?

    private let positions = 20
    private let digits = 3
    private let ticker = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            GameHeader(title: "Duel du coffre", subtitle: subtitle, onBack: { app.route = .coffreLevels }) {
                EmptyView()
            }
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onHingeAngle { degrees in
            guard let degrees, HingeMapping.isOpen(degrees) else {
                usesHinge = false
                return
            }
            usesHinge = true
            let fraction = HingeMapping.fraction(fromDegrees: degrees)
            if case .cracking = phase {
                session?.setFraction(fraction)
            } else {
                dialValue = fraction * Double(positions - 1)
            }
        }
        .onReceive(ticker) { _ in
            guard case .cracking(let player) = phase, let session else { return }
            session.tick(dt: 1.0 / 60.0)
            if session.opened {
                times[player] = session.elapsed
                phase = .roundResult(player: player, time: session.elapsed)
            }
        }
    }

    private var subtitle: String {
        switch phase {
        case .intro: return "2 joueurs, un seul téléphone"
        case .setting(let p): return "Joueur \(p) crée son code"
        case .handover(let c): return "Au tour du joueur \(c)"
        case .cracking(let p): return "Joueur \(p) craque le code"
        case .roundResult: return "Résultat de la manche"
        case .final: return "Résultat final"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .intro:
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "person.2.fill")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundStyle(Theme.gold)
                Text("Chacun cache un code de 3 chiffres. L'autre doit le craquer au toucher. Le plus rapide gagne.")
                    .font(.plie(19, weight: .semibold))
                    .multilineTextAlignment(.center)
                Text("Le joueur 1 commence : il crée son code sans que le joueur 2 regarde.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                Spacer()
                Button("Joueur 1 : créer mon code") {
                    chosen = []
                    phase = .setting(player: 1)
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.gold, textColor: Theme.ink))
            }
            .frame(maxWidth: 520)

        case .setting(let player):
            settingView(player: player)

        case .handover(let cracker):
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "arrow.left.arrow.right.circle.fill")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(Theme.gold)
                Text("Passe le téléphone au joueur \(cracker)")
                    .font(.plie(26))
                    .multilineTextAlignment(.center)
                Text("Joueur \(cracker) : trouve les 3 chiffres. Un clonk plus fort, puis tu restes immobile une seconde.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                Spacer()
                Button("Je suis prêt") {
                    let setter = cracker == 2 ? 1 : 2
                    let level = CoffreLevel(number: 0, digits: digits, positions: positions,
                                            decoysPerDigit: 1, subtle: false, hideNumbers: false)
                    session = CoffreSession(level: level, combination: codes[setter] ?? [3, 12, 7])
                    phase = .cracking(player: cracker)
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.gold, textColor: Theme.ink))
            }
            .frame(maxWidth: 520)

        case .cracking(let player):
            if let session {
                VStack(spacing: 14) {
                    HStack {
                        Text("Joueur \(player)")
                            .font(.plie(18))
                        Spacer()
                        Text(formatSeconds(session.elapsed))
                            .font(.plie(18))
                            .monospacedDigit()
                    }
                    CombinationSlots(total: digits, found: session.found, current: session.found.count, opened: session.opened)
                    Spacer(minLength: 0)
                    CoffreDial(session: session, usesHinge: usesHinge)
                        .frame(maxWidth: 400)
                    Spacer(minLength: 0)
                    CoffreHint(usesHinge: usesHinge)
                }
            }

        case .roundResult(let player, let time):
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundStyle(Theme.gold)
                Text("Joueur \(player) a ouvert le coffre en \(formatSeconds(time))")
                    .font(.plie(24))
                    .multilineTextAlignment(.center)
                Spacer()
                if times.count < 2 {
                    Button("Joueur 2 : créer mon code") {
                        chosen = []
                        phase = .setting(player: 2)
                    }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.gold, textColor: Theme.ink))
                } else {
                    Button("Voir le gagnant") { phase = .final }
                        .buttonStyle(ChunkyButtonStyle(color: Theme.gold, textColor: Theme.ink))
                }
            }
            .frame(maxWidth: 520)

        case .final:
            finalView
        }
    }

    private func settingView(player: Int) -> some View {
        let current = Int(dialValue.rounded())
        return VStack(spacing: 14) {
            Text("Joueur \(player), choisis 3 chiffres")
                .font(.plie(20))
            HStack(spacing: 10) {
                ForEach(0..<digits, id: \.self) { index in
                    Text(index < chosen.count ? String(format: "%02d", chosen[index]) : "•")
                        .font(.plie(24))
                        .monospacedDigit()
                        .foregroundStyle(index < chosen.count ? Theme.ink : .white)
                        .frame(width: 60, height: 60)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(index < chosen.count ? Theme.gold : Theme.card))
                }
            }
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(Theme.card)
                Circle().strokeBorder(Theme.gold.opacity(0.6), lineWidth: 6)
                Text(String(format: "%02d", current))
                    .font(.plie(84))
                    .monospacedDigit()
            }
            .frame(maxWidth: 260, maxHeight: 260)
            .aspectRatio(1, contentMode: .fit)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let delta = Double(value.translation.width - (lastAngle ?? 0))
                        lastAngle = Double(value.translation.width)
                        dialValue = min(Double(positions - 1), max(0, dialValue + delta / 14))
                    }
                    .onEnded { _ in lastAngle = nil }
            )
            Text(usesHinge ? "Plie le téléphone pour choisir un chiffre" : "Glisse le doigt à gauche ou à droite")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.muted)
            Spacer(minLength: 0)
            Button("Garder le \(current)") {
                chosen.append(current)
                Haptics.tap()
                if chosen.count == digits {
                    codes[player] = chosen
                    phase = .handover(cracker: player == 1 ? 2 : 1)
                }
            }
            .buttonStyle(ChunkyButtonStyle(color: Theme.gold, textColor: Theme.ink))
            .disabled(chosen.last == current || current == 0 || current == positions - 1)
            .opacity(chosen.last == current || current == 0 || current == positions - 1 ? 0.5 : 1)
            Text("Le 00 et le \(positions - 1) sont interdits, et deux chiffres de suite doivent être différents.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 520)
    }

    private var finalView: some View {
        let t1 = times[1] ?? .infinity
        let t2 = times[2] ?? .infinity
        let winner = t1 == t2 ? 0 : (t1 < t2 ? 1 : 2)
        return VStack(spacing: 18) {
            Spacer()
            Image(systemName: "trophy.fill")
                .font(.system(size: 60, weight: .bold))
                .foregroundStyle(Theme.gold)
            Text(winner == 0 ? "Égalité parfaite !" : "Le joueur \(winner) gagne !")
                .font(.plie(32))
            VStack(spacing: 8) {
                ForEach([1, 2], id: \.self) { player in
                    HStack {
                        Text("Joueur \(player)")
                            .font(.plie(18, weight: .bold))
                        Spacer()
                        Text(formatSeconds(times[player] ?? 0))
                            .font(.plie(18, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(player == winner ? Theme.gold : .white)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
                }
            }
            Spacer()
            Button("Revanche") {
                codes = [:]
                times = [:]
                chosen = []
                session = nil
                phase = .setting(player: 1)
            }
            .buttonStyle(ChunkyButtonStyle(color: Theme.gold, textColor: Theme.ink))
            Button("Retour") { app.route = .coffreLevels }
                .buttonStyle(GhostButtonStyle())
        }
        .frame(maxWidth: 520)
    }
}
