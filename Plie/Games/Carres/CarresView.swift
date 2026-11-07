import SwiftUI

extension Theme {
    static let carres = Color(hex: 0xFF8A3D)
}

// MARK: - CARRÉS (pipopipette)
//
// Duo ouvert à plat entre deux joueurs. Chacun à son tour trace un trait entre deux points ;
// celui qui ferme un carré le prend (sa couleur et son initiale) et rejoue.
// Seul : contre l'ordinateur.

enum CarresSize: Int, CaseIterable, Identifiable {
    case small, medium, large
    var id: Int { rawValue }
    var cols: Int { [3, 4, 5][rawValue] }
    var rows: Int { [4, 6, 7][rawValue] }
    var title: String { [L("Petit"), L("Moyen"), L("Grand")][rawValue] }
}

@Observable
final class CarresGame {
    enum Phase: Equatable { case menu, playing, over }
    /// Un trait : horizontal (entre (r, c) et (r, c+1)) ou vertical (entre (r, c) et (r+1, c)).
    struct Edge: Hashable { let horizontal: Bool; let r: Int; let c: Int }

    static let colors: [Color] = [Color(hex: 0x3D8BFF), Color(hex: 0xFF4F7B)]

    private(set) var phase: Phase = .menu
    private(set) var size: CarresSize = .medium
    var vsComputer = false
    var initials = ["A", "B"]
    private(set) var edges: [Edge: Int] = [:]
    private(set) var boxes: [Int] = []
    private(set) var turn = 0
    private(set) var lastEdge: Edge?
    private(set) var thinking = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var starter = 0

    var cols: Int { size.cols }
    var rows: Int { size.rows }
    func score(_ p: Int) -> Int { boxes.filter { $0 == p }.count }
    var humanTurn: Bool { phase == .playing && !thinking && !(vsComputer && turn == 1) }

    var allEdges: [Edge] {
        var out: [Edge] = []
        for r in 0...rows { for c in 0..<cols { out.append(Edge(horizontal: true, r: r, c: c)) } }
        for r in 0..<rows { for c in 0...cols { out.append(Edge(horizontal: false, r: r, c: c)) } }
        return out
    }

    func start(_ s: CarresSize) {
        size = s
        edges = [:]
        boxes = Array(repeating: -1, count: s.cols * s.rows)
        lastEdge = nil
        thinking = false
        turn = starter
        generation += 1
        phase = .playing
        computerIfNeeded()
    }

    func rematch() { starter = 1 - starter; start(size) }
    func backToMenu() { generation += 1; phase = .menu }

    func cycleInitial(_ p: Int) {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let cur = letters.firstIndex(of: Character(initials[p])) ?? 0
        var next = letters[(cur + 1) % letters.count]
        if String(next) == initials[1 - p] { next = letters[(cur + 2) % letters.count] }
        initials[p] = String(next)
        Haptics.tap()
    }

    /// Les carrés touchés par un trait.
    private func boxesOf(_ e: Edge) -> [Int] {
        var out: [Int] = []
        if e.horizontal {
            if e.r > 0 { out.append((e.r - 1) * cols + e.c) }
            if e.r < rows { out.append(e.r * cols + e.c) }
        } else {
            if e.c > 0 { out.append(e.r * cols + e.c - 1) }
            if e.c < cols { out.append(e.r * cols + e.c) }
        }
        return out
    }

    private func sides(_ b: Int, _ map: [Edge: Int]) -> Int {
        let r = b / cols, c = b % cols
        return [Edge(horizontal: true, r: r, c: c), Edge(horizontal: true, r: r + 1, c: c),
                Edge(horizontal: false, r: r, c: c), Edge(horizontal: false, r: r, c: c + 1)].filter { map[$0] != nil }.count
    }

    func tap(_ e: Edge) {
        guard humanTurn else { return }
        play(e)
    }

    private func play(_ e: Edge) {
        guard edges[e] == nil, phase == .playing else { return }
        edges[e] = turn
        lastEdge = e
        var closed = 0
        for b in boxesOf(e) where boxes[b] < 0 && sides(b, edges) == 4 {
            boxes[b] = turn
            closed += 1
        }
        if closed > 0 {
            SoundPlayer.shared.play(.chime, volume: 0.6)
            Haptics.success()
        } else {
            SoundPlayer.shared.play(.chalk, volume: 0.5)
            Haptics.tap()
            turn = 1 - turn
        }
        if !boxes.contains(-1) {
            phase = .over
            SoundPlayer.shared.play(.win, volume: 0.8)
            return
        }
        computerIfNeeded()
    }

    private func computerIfNeeded() {
        guard vsComputer, turn == 1, phase == .playing else { return }
        thinking = true
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            guard let self, self.generation == gen, self.phase == .playing else { return }
            self.thinking = false
            if let e = self.bestEdge() { self.play(e) }
        }
    }

    /// L'ordinateur : prend un carré s'il peut ; sinon évite de donner un 3e côté ; sinon donne le moins possible.
    private func bestEdge() -> Edge? {
        let free = allEdges.filter { edges[$0] == nil }
        guard !free.isEmpty else { return nil }
        if let take = free.first(where: { e in boxesOf(e).contains { boxes[$0] < 0 && sides($0, edges) == 3 } }) { return take }
        let safe = free.filter { e in boxesOf(e).allSatisfy { sides($0, edges) < 2 } }
        if let s = safe.randomElement() { return s }
        // Donner la plus petite chaîne possible
        var best: Edge?
        var bestGift = Int.max
        for e in free.shuffled().prefix(40) {
            var map = edges
            map[e] = 0
            var gift = 0
            var changed = true
            var taken = Set<Int>()
            while changed {
                changed = false
                for b in 0..<(cols * rows) where boxes[b] < 0 && !taken.contains(b) && sides(b, map) == 3 {
                    let r = b / cols, c = b % cols
                    for x in [Edge(horizontal: true, r: r, c: c), Edge(horizontal: true, r: r + 1, c: c),
                              Edge(horizontal: false, r: r, c: c), Edge(horizontal: false, r: r, c: c + 1)] where map[x] == nil { map[x] = 1 }
                    taken.insert(b); gift += 1; changed = true
                }
            }
            if gift < bestGift { bestGift = gift; best = e }
        }
        return best ?? free.randomElement()
    }

    #if DEBUG
    func demo() {
        vsComputer = false
        start(.medium)
        for e in allEdges.shuffled().prefix(26) where phase == .playing { play(e) }
    }
    #endif
}

struct CarresView: View {
    @Environment(AppState.self) private var app
    @State private var game = CarresGame()

    var body: some View {
        ZStack {
            Color(hex: 0xF7F0E2).ignoresSafeArea()
            if game.phase == .menu {
                VStack { header; menu }
            } else {
                FaceToFace { seat in
                    panel(seat)
                }
                CarresBoard(game: game)
                    .padding(.horizontal, 18)
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, 110)
                VStack { header; Spacer() }
                if game.phase == .over { result }
            }
        }
        .foregroundStyle(Color(hex: 0x2A2438))
        .onChange(of: game.phase) { _, p in
            if p == .over {
                app.gamePlayed()
                if game.vsComputer && game.score(0) > game.score(1) { app.celebrate() }
            }
        }
        .onAppear {
            #if DEBUG
            Demo.schedule("carres", [(0.0, { game.demo() })])
            #endif
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconButton(symbol: "chevron.left", label: L("Retour")) {
                if game.phase == .menu { app.route = .hub } else { game.backToMenu() }
            }
            HowToButton(game: .carres)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var menu: some View {
        VStack(spacing: 14) {
            Spacer()
            Text(L("CARRÉS")).font(.plie(34))
            Text(L("Trace un trait à ton tour. Ferme un carré pour le prendre, et rejoue.")).font(.plie(17, weight: .semibold)).multilineTextAlignment(.center).opacity(0.75)
            Picker("", selection: Binding(get: { game.vsComputer }, set: { game.vsComputer = $0 })) {
                Text(L("À deux")).tag(false)
                Text(L("Contre l'ordinateur")).tag(true)
            }
            .pickerStyle(.segmented)
            ForEach(CarresSize.allCases) { s in
                Button(L("\(s.title) · \(s.cols * s.rows) carrés")) { game.start(s) }
                    .buttonStyle(ChunkyButtonStyle(color: [Color(hex: 0x3D8BFF), Theme.carres, Color(hex: 0xFF4F7B)][s.rawValue]))
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 520)
    }

    /// Le côté de chaque joueur : son initiale (on la change en touchant), son score, à qui de jouer.
    private func panel(_ seat: Int) -> some View {
        let p = seat
        let mine = game.turn == p && game.phase == .playing
        return VStack {
            Spacer()
            HStack(spacing: 14) {
                Button { if game.edges.isEmpty { game.cycleInitial(p) } } label: {
                    Text(verbatim: game.initials[p])
                        .font(.plie(26))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CarresGame.colors[p]))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(L("Ton initiale"))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("\(game.score(p)) carrés")).font(.plie(22))
                    Text(p == 1 && game.vsComputer ? (mine ? L("L'ordinateur réfléchit…") : L("Ordinateur")) : (mine ? L("À toi de jouer") : L("Attends ton tour")))
                        .font(.plie(14, weight: .bold))
                        .foregroundStyle(mine ? CarresGame.colors[p] : Color(hex: 0x2A2438, opacity: 0.5))
                }
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 14)
            .opacity(mine || game.phase == .over ? 1 : 0.7)
        }
    }

    private var result: some View {
        let a = game.score(0), b = game.score(1)
        let text = a == b ? L("Égalité !") : L("\(a > b ? game.initials[0] : game.initials[1]) gagne \(max(a, b)) à \(min(a, b)) !")
        return VStack(spacing: 14) {
            Text(text).font(.plie(28)).multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button(L("Revanche")) { game.rematch() }.buttonStyle(ChunkyButtonStyle(color: Theme.carres))
                Button(L("Menu")) { game.backToMenu() }.buttonStyle(ChunkyButtonStyle(color: Color(hex: 0x2A2438, opacity: 0.6)))
            }
        }
        .padding(22)
        .frame(maxWidth: 380)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.white).shadow(color: .black.opacity(0.15), radius: 20, y: 8))
        .padding(24)
    }
}

/// La grille : points, traits, carrés pris. On touche près d'un trait pour le tracer.
struct CarresBoard: View {
    let game: CarresGame

    var body: some View {
        GeometryReader { proxy in
            let cols = CGFloat(game.cols), rows = CGFloat(game.rows)
            let step = min(proxy.size.width / (cols + 0.6), proxy.size.height / (rows + 0.6))
            let w = step * cols, h = step * rows
            let ox = (proxy.size.width - w) / 2, oy = (proxy.size.height - h) / 2
            ZStack {
                Canvas { ctx, _ in
                    // Carrés pris : couleur et initiale (tournée vers celui qui l'a pris)
                    for b in game.boxes.indices where game.boxes[b] >= 0 {
                        let p = game.boxes[b]
                        let r = CGFloat(b / game.cols), c = CGFloat(b % game.cols)
                        let rect = CGRect(x: ox + c * step, y: oy + r * step, width: step, height: step).insetBy(dx: 3, dy: 3)
                        ctx.fill(Path(roundedRect: rect, cornerRadius: 8), with: .color(CarresGame.colors[p].opacity(0.85)))
                        var t = ctx
                        t.translateBy(x: rect.midX, y: rect.midY)
                        if p == 1 && !game.vsComputer { t.rotate(by: .degrees(180)) }
                        t.draw(Text(verbatim: game.initials[p]).font(.system(size: step * 0.45, weight: .heavy, design: .rounded)).foregroundColor(.white), at: .zero)
                    }
                    // Traits
                    for (e, p) in game.edges {
                        let a = CGPoint(x: ox + CGFloat(e.c) * step, y: oy + CGFloat(e.r) * step)
                        let b = e.horizontal ? CGPoint(x: a.x + step, y: a.y) : CGPoint(x: a.x, y: a.y + step)
                        var path = Path(); path.move(to: a); path.addLine(to: b)
                        let last = e == game.lastEdge
                        ctx.stroke(path, with: .color(CarresGame.colors[p]), style: StrokeStyle(lineWidth: last ? 7 : 5, lineCap: .round))
                    }
                    // Points
                    for r in 0...game.rows {
                        for c in 0...game.cols {
                            let pt = CGPoint(x: ox + CGFloat(c) * step, y: oy + CGFloat(r) * step)
                            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)), with: .color(Color(hex: 0x2A2438)))
                        }
                    }
                }
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { v in
                        if let e = nearest(v.location, ox: ox, oy: oy, step: step) { game.tap(e) }
                    })
            }
        }
    }

    /// Le trait libre le plus proche du doigt (à moins d'un demi-pas).
    private func nearest(_ p: CGPoint, ox: CGFloat, oy: CGFloat, step: CGFloat) -> CarresGame.Edge? {
        var best: CarresGame.Edge?
        var bestD = step * 0.45
        for e in game.allEdges where game.edges[e] == nil {
            let mid = e.horizontal ? CGPoint(x: ox + (CGFloat(e.c) + 0.5) * step, y: oy + CGFloat(e.r) * step)
                                   : CGPoint(x: ox + CGFloat(e.c) * step, y: oy + (CGFloat(e.r) + 0.5) * step)
            let d = hypot(p.x - mid.x, p.y - mid.y)
            if d < bestD { bestD = d; best = e }
        }
        return best
    }
}
