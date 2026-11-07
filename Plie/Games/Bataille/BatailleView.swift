import SwiftUI

extension Theme {
    static let bataille = Color(hex: 0x2EC4B6)
}

// MARK: - BATAILLE NAVALE
//
// Chaque joueur a sa flotte cachée. On tire sur la grille d'en face (moitié haute),
// sa propre flotte est en bas. À deux : après chaque tir, on FERME le Duo et on le passe :
// le pli cache les grilles. Seul : contre l'ordinateur.

struct Ship: Equatable {
    var cells: [Int]
    var size: Int { cells.count }
}

struct Fleet: Equatable {
    static let n = 8
    static let sizes = [4, 3, 3, 2, 2]
    var ships: [Ship] = []
    /// Tirs reçus : nil = rien, false = dans l'eau, true = touché.
    var shots: [Bool?] = Array(repeating: nil, count: n * n)

    func ship(at i: Int) -> Int? { ships.firstIndex { $0.cells.contains(i) } }
    func sunk(_ k: Int) -> Bool { ships[k].cells.allSatisfy { shots[$0] == true } }
    var allSunk: Bool { ships.indices.allSatisfy { sunk($0) } }

    /// Place la flotte au hasard (les bateaux ne se touchent pas, même en diagonale).
    static func random() -> Fleet {
        while true {
            var f = Fleet()
            var taken = Set<Int>()
            var ok = true
            for s in sizes {
                var placed = false
                for _ in 0..<200 {
                    let horiz = Bool.random()
                    let r = Int.random(in: 0..<(horiz ? n : n - s + 1)), c = Int.random(in: 0..<(horiz ? n - s + 1 : n))
                    let cells = (0..<s).map { horiz ? r * n + c + $0 : (r + $0) * n + c }
                    if cells.allSatisfy({ !taken.contains($0) }) {
                        f.ships.append(Ship(cells: cells))
                        for x in cells {
                            let xr = x / n, xc = x % n
                            for dr in -1...1 { for dc in -1...1 {
                                let rr = xr + dr, cc = xc + dc
                                if rr >= 0, rr < n, cc >= 0, cc < n { taken.insert(rr * n + cc) }
                            } }
                        }
                        placed = true
                        break
                    }
                }
                if !placed { ok = false; break }
            }
            if ok { return f }
        }
    }
}

@Observable
final class BatailleGame {
    enum Phase: Equatable { case menu, placing, pass, aiming, shot, over }
    enum Shot: Equatable { case miss, hit, sunk }

    private(set) var phase: Phase = .menu
    var vsComputer = true
    private(set) var fleets = [Fleet(), Fleet()]
    /// Joueur dont c'est le tour (0 ou 1).
    private(set) var turn = 0
    private(set) var placing = 0
    private(set) var lastShot: (cell: Int, result: Shot)?
    private(set) var winner = -1
    /// Le Duo a été fermé pendant le passage (on attend qu'il soit rouvert).
    private(set) var closedDuringPass = false
    /// Passage du Duo : à qui on le donne, et ce qu'il fera ensuite.
    private(set) var passTo = 0
    @ObservationIgnored private var passThen: Phase = .aiming
    private(set) var hasHinge = false
    @ObservationIgnored private var aiTargets: [Int] = []
    @ObservationIgnored private var generation = 0

    var me: Fleet { fleets[turn] }
    var them: Fleet { fleets[1 - turn] }

    func start() {
        fleets = [Fleet.random(), Fleet.random()]
        turn = 0
        placing = 0
        winner = -1
        lastShot = nil
        aiTargets = []
        generation += 1
        phase = .placing
    }

    func backToMenu() { generation += 1; phase = .menu }

    func shuffle() {
        fleets[placing] = Fleet.random()
        SoundPlayer.shared.play(.whoosh, volume: 0.5)
        Haptics.tap()
    }

    /// Le joueur a fini de placer ses bateaux.
    func ready() {
        if vsComputer {
            turn = 0
            phase = .aiming
        } else if placing == 0 {
            placing = 1
            beginPass(to: 1, then: .placing)
        } else {
            turn = 0
            beginPass(to: 0, then: .aiming)
        }
    }

    private func beginPass(to player: Int, then next: Phase) {
        passTo = player
        passThen = next
        closedDuringPass = false
        phase = .pass
    }

    /// Fin du passage : le bon joueur a le Duo en main.
    func takeOver() {
        guard phase == .pass else { return }
        phase = passThen
        Haptics.tap()
    }

    func hinge(_ degrees: Double?) {
        guard let degrees else { return }
        hasHinge = true
        guard phase == .pass else { return }
        if !HingeMapping.isOpen(degrees) {
            closedDuringPass = true
        } else if closedDuringPass && degrees > 60 {
            takeOver()
        }
    }

    func fire(_ i: Int) {
        guard phase == .aiming, them.shots[i] == nil else { return }
        if vsComputer && turn == 1 { return }
        resolve(i, by: turn)
    }

    private func resolve(_ i: Int, by shooter: Int) {
        let target = 1 - shooter
        var f = fleets[target]
        let k = f.ship(at: i)
        f.shots[i] = k != nil
        fleets[target] = f
        let result: Shot = k == nil ? .miss : (f.sunk(k!) ? .sunk : .hit)
        lastShot = (i, result)
        switch result {
        case .miss: SoundPlayer.shared.play(.splat, volume: 0.6); Haptics.tap()
        case .hit: SoundPlayer.shared.play(.boom, volume: 0.6); Haptics.success()
        case .sunk: SoundPlayer.shared.play(.boom, volume: 0.9); Haptics.success()
        }
        if f.allSunk {
            winner = shooter
            phase = .over
            SoundPlayer.shared.play(.win, volume: 0.8)
            return
        }
        phase = .shot
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in
            guard let self, self.generation == gen, self.phase == .shot else { return }
            self.nextTurn()
        }
    }

    private func nextTurn() {
        turn = 1 - turn
        if vsComputer {
            phase = .aiming
            if turn == 1 { computerFire() }
        } else {
            beginPass(to: turn, then: .aiming)
        }
    }

    /// L'ordinateur : vise autour d'une touche, sinon tire en damier.
    private func computerFire() {
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, self.generation == gen, self.phase == .aiming, self.turn == 1 else { return }
            let shots = self.fleets[0].shots
            let n = Fleet.n
            self.aiTargets = self.aiTargets.filter { shots[$0] == nil }
            var cell = self.aiTargets.popLast()
            if cell == nil {
                let free = (0..<(n * n)).filter { shots[$0] == nil }
                let parity = free.filter { ($0 / n + $0 % n) % 2 == 0 }
                cell = (parity.isEmpty ? free : parity).randomElement()
            }
            guard let c = cell else { return }
            let hit = self.fleets[0].ship(at: c) != nil
            self.resolve(c, by: 1)
            if hit {
                let r = c / n, col = c % n
                for (dr, dc) in [(0, 1), (0, -1), (1, 0), (-1, 0)] {
                    let rr = r + dr, cc = col + dc
                    if rr >= 0, rr < n, cc >= 0, cc < n, self.fleets[0].shots[rr * n + cc] == nil { self.aiTargets.append(rr * n + cc) }
                }
            }
        }
    }

    #if DEBUG
    func demo() {
        vsComputer = true
        start()
        ready()
        for _ in 0..<14 {
            let free = (0..<64).filter { fleets[1].shots[$0] == nil }
            if let c = free.randomElement() { var f = fleets[1]; f.shots[c] = f.ship(at: c) != nil; fleets[1] = f }
            let free0 = (0..<64).filter { fleets[0].shots[$0] == nil }
            if let c = free0.randomElement() { var f = fleets[0]; f.shots[c] = f.ship(at: c) != nil; fleets[0] = f }
        }
    }
    #endif
}

struct BatailleView: View {
    @Environment(AppState.self) private var app
    @State private var game = BatailleGame()

    var body: some View {
        ZStack {
            SeaBackdrop()
            switch game.phase {
            case .menu: VStack { header; menu }
            case .placing: placing
            case .pass: pass
            case .aiming, .shot, .over: battle
            }
            if game.phase == .over { result }
        }
        .foregroundStyle(.white)
        .onHingeAngle { game.hinge($0) }
        .onChange(of: game.phase) { _, p in
            if p == .over {
                app.gamePlayed()
                if !game.vsComputer || game.winner == 0 { app.celebrate() }
            }
        }
        .onAppear {
            #if DEBUG
            Demo.schedule("bataille", [(0.0, { game.demo() })])
            #endif
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconButton(symbol: "chevron.left", label: L("Retour")) {
                if game.phase == .menu { app.route = .hub } else { game.backToMenu() }
            }
            HowToButton(game: .bataille)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var menu: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "scope").font(.system(size: 56, weight: .bold)).foregroundStyle(Theme.bataille)
            Text(L("BATAILLE NAVALE")).font(.plie(32))
            Text(L("Coule les 5 bateaux de l'autre avant qu'il coule les tiens.")).font(.plie(17, weight: .semibold)).multilineTextAlignment(.center).opacity(0.8)
            Button(L("Contre l'ordinateur")) { game.vsComputer = true; game.start() }
                .buttonStyle(ChunkyButtonStyle(color: Theme.bataille))
            Button(L("À deux : on se passe le Duo")) { game.vsComputer = false; game.start() }
                .buttonStyle(ChunkyButtonStyle(color: Color(hex: 0xFF8A3D)))
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 520)
    }

    // Mise en place
    private var placing: some View {
        VStack(spacing: 14) {
            header
            Text(game.vsComputer ? L("Ta flotte") : L("Flotte du joueur \(game.placing + 1)")).font(.plie(26))
            Text(L("Ne montre pas ta grille ! Mélange jusqu'à ce qu'elle te plaise.")).font(.plie(15, weight: .semibold)).opacity(0.8).multilineTextAlignment(.center)
            BatailleGrid(fleet: game.fleets[game.placing], showShips: true, onTap: nil)
                .padding(.horizontal, 20)
            HStack(spacing: 10) {
                Button { game.shuffle() } label: { Label(L("Mélanger"), systemImage: "shuffle") }
                    .buttonStyle(ChunkyButtonStyle(color: Color.white.opacity(0.2)))
                Button(L("Prêt")) { game.ready() }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.go))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: 560)
    }

    // Passage du Duo : le pli cache les grilles
    private var pass: some View {
        let next = game.passTo + 1
        return VStack(spacing: 18) {
            Spacer()
            Image(systemName: game.hasHinge ? "iphone.gen3.radiowaves.left.and.right" : "hand.raised.fill")
                .font(.system(size: 54, weight: .bold))
                .foregroundStyle(Theme.bataille)
            if let s = game.lastShot {
                Text(s.result == .miss ? L("Dans l'eau.") : (s.result == .sunk ? L("Coulé !") : L("Touché !"))).font(.plie(30))
            }
            Text(L("Au tour du joueur \(next)")).font(.plie(28))
            Text(game.hasHinge ? L("Ferme le Duo, passe-le, puis rouvre-le.") : L("Passe le téléphone sans regarder."))
                .font(.plie(17, weight: .semibold)).opacity(0.85).multilineTextAlignment(.center)
            Button(L("C'est moi, joueur \(next)")) { game.takeOver() }
                .buttonStyle(ChunkyButtonStyle(color: Theme.bataille))
                .padding(.horizontal, 30)
            Spacer()
        }
        .padding(24)
    }

    // La bataille : en haut la mer d'en face, en bas ta flotte (le pli du Duo les sépare)
    private var battle: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    header
                    Text(turnTitle).font(.plie(20))
                    BatailleGrid(fleet: game.them, showShips: game.phase == .over, onTap: { game.fire($0) }, highlight: game.turn == 0 || !game.vsComputer ? game.lastShot?.cell : nil)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
                .frame(height: proxy.size.height / 2)
                VStack(spacing: 6) {
                    Text(game.vsComputer ? L("Ta flotte") : L("Ta flotte (joueur \(game.turn + 1))")).font(.plie(15, weight: .bold)).opacity(0.8).padding(.top, 10)
                    BatailleGrid(fleet: game.me, showShips: true, onTap: nil)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 10)
                }
                .frame(height: proxy.size.height / 2)
            }
        }
    }

    private var turnTitle: String {
        if game.phase == .over { return game.winner == 0 || !game.vsComputer ? L("Victoire !") : L("Perdu…") }
        if let s = game.lastShot, game.phase == .shot {
            return s.result == .miss ? L("Dans l'eau.") : (s.result == .sunk ? L("Coulé !") : L("Touché !"))
        }
        if game.vsComputer { return game.turn == 0 ? L("Touche une case pour tirer") : L("L'ordinateur vise…") }
        return L("Joueur \(game.turn + 1) : tire !")
    }

    private var result: some View {
        let text = game.vsComputer ? (game.winner == 0 ? L("Tu as coulé toute la flotte !") : L("L'ordinateur a gagné.")) : L("Le joueur \(game.winner + 1) gagne !")
        return VStack(spacing: 14) {
            Text(text).font(.plie(26)).multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button(L("Rejouer")) { game.start() }.buttonStyle(ChunkyButtonStyle(color: Theme.bataille))
                Button(L("Menu")) { game.backToMenu() }.buttonStyle(ChunkyButtonStyle(color: Color.white.opacity(0.18)))
            }
        }
        .padding(22)
        .frame(maxWidth: 380)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(hex: 0x0B2A3A).opacity(0.97)))
        .padding(24)
    }
}

struct BatailleGrid: View {
    let fleet: Fleet
    let showShips: Bool
    let onTap: ((Int) -> Void)?
    var highlight: Int? = nil

    var body: some View {
        GeometryReader { proxy in
            let n = Fleet.n
            let side = min(proxy.size.width, proxy.size.height) / CGFloat(n)
            let w = side * CGFloat(n)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: 0x0E4A6B))
                ForEach(0..<(n * n), id: \.self) { i in
                    let r = i / n, c = i % n
                    cell(i, side: side)
                        .offset(x: CGFloat(c) * side, y: CGFloat(r) * side)
                }
            }
            .frame(width: w, height: w)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    @ViewBuilder
    private func cell(_ i: Int, side: CGFloat) -> some View {
        let shot = fleet.shots[i]
        let k = fleet.ship(at: i)
        let sunk = k.map { fleet.sunk($0) } ?? false
        ZStack {
            Rectangle().stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            if showShips || sunk, k != nil {
                RoundedRectangle(cornerRadius: side * 0.2, style: .continuous)
                    .fill(sunk ? Color(hex: 0x5A2A2A) : Color(hex: 0x9AA8B8))
                    .padding(side * 0.08)
            }
            if shot == false {
                Circle().fill(Color.white.opacity(0.75)).frame(width: side * 0.22)
            } else if shot == true {
                Image(systemName: "flame.fill").font(.system(size: side * 0.55, weight: .bold)).foregroundStyle(Color(hex: 0xFF6A3D))
            }
            if highlight == i {
                Rectangle().stroke(Color(hex: 0xFFE066), lineWidth: 3)
            }
        }
        .frame(width: side, height: side)
        .contentShape(Rectangle())
        .onTapGesture { onTap?(i) }
    }
}

struct SeaBackdrop: View {
    var body: some View {
        LinearGradient(colors: [Color(hex: 0x06263A), Color(hex: 0x0A3D57)], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}
