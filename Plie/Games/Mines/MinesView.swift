import SwiftUI

extension Theme {
    static let mines = Color(hex: 0x4FC3F7)
}

// MARK: - DÉMINEUR
//
// Le classique, en solo. Sur le Duo : plie un peu le téléphone pour passer en mode drapeau,
// déplie-le à plat pour creuser. (Sans Duo : le bouton pelle / drapeau.)

enum MinesSize: Int, CaseIterable, Identifiable {
    case kids, normal, hard
    var id: Int { rawValue }
    var cols: Int { [7, 9, 12][rawValue] }
    var rows: Int { [9, 12, 16][rawValue] }
    var mines: Int { [7, 18, 38][rawValue] }
    var title: String { [L("Petit"), L("Moyen"), L("Grand")][rawValue] }
}

@Observable
final class MinesGame {
    enum Phase: Equatable { case menu, playing, won, lost }
    enum Cell: Equatable { case hidden, flagged, open }

    private(set) var phase: Phase = .menu
    private(set) var size: MinesSize = .normal
    private(set) var mine: [Bool] = []
    private(set) var count: [Int] = []
    private(set) var cells: [Cell] = []
    private(set) var exploded: Int?
    private(set) var started: Date?
    private(set) var finishedTime: Double?
    var flagMode = false
    /// Le Duo est un peu plié : on pose des drapeaux.
    private(set) var hingeFlag = false
    private(set) var usesHinge = false

    var cols: Int { size.cols }
    var rows: Int { size.rows }
    var flagsLeft: Int { size.mines - cells.filter { $0 == .flagged }.count }
    var flagging: Bool { flagMode != hingeFlag }

    func best(_ s: MinesSize) -> Double? {
        let v = UserDefaults.standard.double(forKey: "mines.best.\(s.rawValue)")
        return v > 0 ? v : nil
    }

    func start(_ s: MinesSize) {
        size = s
        let n = s.cols * s.rows
        mine = Array(repeating: false, count: n)
        count = Array(repeating: 0, count: n)
        cells = Array(repeating: .hidden, count: n)
        exploded = nil
        started = nil
        finishedTime = nil
        flagMode = false
        phase = .playing
    }

    func restart() { start(size) }
    func backToMenu() { phase = .menu }

    func hinge(_ degrees: Double?) {
        guard let degrees, HingeMapping.isOpen(degrees) else { return }
        usesHinge = true
        let folded = degrees < 150
        if folded != hingeFlag {
            hingeFlag = folded
            Haptics.tap()
        }
    }

    private func neighbors(_ i: Int) -> [Int] {
        let c = i % cols, r = i / cols
        var out: [Int] = []
        for dr in -1...1 {
            for dc in -1...1 where !(dr == 0 && dc == 0) {
                let rr = r + dr, cc = c + dc
                if rr >= 0, rr < rows, cc >= 0, cc < cols { out.append(rr * cols + cc) }
            }
        }
        return out
    }

    /// Les mines sont posées au premier toucher : jamais sous le doigt ni juste autour.
    private func layMines(safe: Int) {
        let banned = Set(neighbors(safe) + [safe])
        var spots = Array(0..<(cols * rows)).filter { !banned.contains($0) }
        spots.shuffle()
        for i in spots.prefix(size.mines) { mine[i] = true }
        for i in 0..<(cols * rows) { count[i] = neighbors(i).filter { mine[$0] }.count }
        started = Date()
    }

    func tap(_ i: Int) {
        guard phase == .playing else { return }
        if flagging { toggleFlag(i); return }
        if cells[i] == .open { chord(i); return }
        guard cells[i] == .hidden else { return }
        if started == nil { layMines(safe: i) }
        open(i)
    }

    func toggleFlag(_ i: Int) {
        guard phase == .playing, cells[i] != .open else { return }
        cells[i] = cells[i] == .flagged ? .hidden : .flagged
        Haptics.tap()
        SoundPlayer.shared.play(.pok, volume: 0.5)
    }

    /// Toucher un chiffre déjà ouvert, quand tous ses drapeaux sont posés : ouvre le reste autour.
    private func chord(_ i: Int) {
        let n = neighbors(i)
        guard count[i] > 0, n.filter({ cells[$0] == .flagged }).count == count[i] else { return }
        for j in n where cells[j] == .hidden { open(j); if phase != .playing { return } }
    }

    private func open(_ i: Int) {
        if mine[i] {
            exploded = i
            for j in mine.indices where mine[j] && cells[j] != .flagged { cells[j] = .open }
            phase = .lost
            SoundPlayer.shared.play(.boom, volume: 0.8)
            Haptics.error()
            return
        }
        // Ouverture en cascade des zones vides
        var stack = [i]
        var opened = 0
        while let k = stack.popLast() {
            guard cells[k] == .hidden else { continue }
            cells[k] = .open
            opened += 1
            if count[k] == 0 { stack.append(contentsOf: neighbors(k).filter { cells[$0] == .hidden }) }
        }
        SoundPlayer.shared.play(opened > 4 ? .whoosh : .tock, volume: 0.5)
        Haptics.tap()
        let safe = mine.indices.filter { !mine[$0] }
        if safe.allSatisfy({ cells[$0] == .open }) {
            let t = Date().timeIntervalSince(started ?? Date())
            finishedTime = t
            for j in mine.indices where mine[j] { cells[j] = .flagged }
            let key = "mines.best.\(size.rawValue)"
            let old = UserDefaults.standard.double(forKey: key)
            if old == 0 || t < old { UserDefaults.standard.set(t, forKey: key) }
            let board: Leaderboard = size == .kids ? .minesKids : (size == .hard ? .minesHard : .minesNormal)
            GameCenter.shared.submit(Int((t * 100).rounded()), to: board)
            phase = .won
            SoundPlayer.shared.play(.win, volume: 0.8)
            Haptics.success()
        }
    }

    #if DEBUG
    /// Captures : une partie bien avancée.
    func demo() {
        start(.normal)
        layMines(safe: cols * (rows / 2) + cols / 2)
        tap(cols * (rows / 2) + cols / 2)
        var k = 0
        for i in mine.indices where mine[i] && k < 6 { cells[i] = .flagged; k += 1 }
    }
    #endif
}

struct MinesView: View {
    @Environment(AppState.self) private var app
    @State private var game = MinesGame()

    var body: some View {
        ZStack {
            MinesBackdrop()
            VStack(spacing: 12) {
                header
                if game.phase == .menu {
                    menu
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in status(ctx.date) }
                    MinesBoard(game: game)
                        .padding(.horizontal, 10)
                    controls
                }
            }
            .padding(.bottom, 10)
            if game.phase == .won || game.phase == .lost { result }
        }
        .foregroundStyle(.white)
        .onHingeAngle { game.hinge($0) }
        .onChange(of: game.phase) { _, p in
            if p == .won { app.gamePlayed(); app.celebrate() }
            if p == .lost { app.gamePlayed() }
        }
        .onAppear {
            #if DEBUG
            Demo.schedule("mines", [(0.0, { game.demo() })])
            #endif
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconButton(symbol: "chevron.left", label: L("Retour")) {
                if game.phase == .menu { app.route = .hub } else { game.backToMenu() }
            }
            HowToButton(game: .mines)
            Text(L("DÉMINEUR")).font(.plie(22))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var menu: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "flag.checkered").font(.system(size: 56, weight: .bold)).foregroundStyle(Theme.mines)
            Text(L("Trouve toutes les cases sans mine.")).font(.plie(18, weight: .bold)).multilineTextAlignment(.center)
            ForEach(MinesSize.allCases) { s in
                Button { game.start(s) } label: {
                    HStack {
                        Text(s.title)
                        Spacer()
                        Text(L("\(s.mines) mines")).opacity(0.8)
                        if let b = game.best(s) { Text(verbatim: "· \(Int(b)) s").opacity(0.8) }
                    }
                }
                .buttonStyle(ChunkyButtonStyle(color: [Color(hex: 0x3FB37F), Theme.mines, Color(hex: 0xE8605A)][s.rawValue]))
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 520)
    }

    private func status(_ now: Date) -> some View {
        let t = game.finishedTime ?? game.started.map { now.timeIntervalSince($0) } ?? 0
        return HStack(spacing: 18) {
            Label { Text(verbatim: "\(game.flagsLeft)") } icon: { Image(systemName: "flag.fill").foregroundStyle(Theme.coral) }
            Label { Text(verbatim: "\(Int(t)) s") } icon: { Image(systemName: "timer") }
        }
        .font(.plie(20))
        .monospacedDigit()
    }

    private var controls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                modeButton(flag: false)
                modeButton(flag: true)
            }
            .frame(maxWidth: 420)
            Text(game.usesHinge ? L("Plie un peu le Duo pour poser des drapeaux.") : L("Appui long : poser un drapeau."))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .opacity(0.7)
        }
        .padding(.horizontal, 20)
    }

    private func modeButton(flag: Bool) -> some View {
        let on = game.flagging == flag
        return Button {
            game.flagMode = flag != game.hingeFlag
            Haptics.tap()
        } label: {
            Label(flag ? L("Drapeau") : L("Creuser"), systemImage: flag ? "flag.fill" : "hand.point.up.left.fill")
                .font(.plie(17))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(on ? (flag ? Theme.coral : Theme.mines) : Color.white.opacity(0.1)))
                .foregroundStyle(.white)
        }
        .buttonStyle(PressableStyle())
    }

    private var result: some View {
        let won = game.phase == .won
        return VStack(spacing: 14) {
            Text(won ? L("Bravo, déminé !") : L("Boum !")).font(.plie(30))
            if won, let t = game.finishedTime { Text(L("En \(Int(t)) secondes")).font(.plie(18, weight: .bold)).opacity(0.85) }
            HStack(spacing: 10) {
                Button(L("Rejouer")) { game.restart() }.buttonStyle(ChunkyButtonStyle(color: won ? Theme.go : Theme.coral))
                Button(L("Menu")) { game.backToMenu() }.buttonStyle(ChunkyButtonStyle(color: Color.white.opacity(0.18)))
            }
        }
        .padding(22)
        .frame(maxWidth: 380)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(hex: 0x10233A).opacity(0.96)))
        .padding(24)
        .transition(.scale.combined(with: .opacity))
    }
}

struct MinesBoard: View {
    let game: MinesGame

    static let numberColors: [Color] = [.clear, Color(hex: 0x1E6FD9), Color(hex: 0x2E9E4F), Color(hex: 0xD93636), Color(hex: 0x6A3DC9),
                                        Color(hex: 0xA0522D), Color(hex: 0x138A8A), Color(hex: 0x222222), Color(hex: 0x777777)]

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width / CGFloat(game.cols), proxy.size.height / CGFloat(game.rows))
            let w = side * CGFloat(game.cols), h = side * CGFloat(game.rows)
            VStack(spacing: 0) {
                ForEach(0..<game.rows, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<game.cols, id: \.self) { c in
                            cell(r * game.cols + c, side: side)
                        }
                    }
                }
            }
            .frame(width: w, height: h)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    @ViewBuilder
    private func cell(_ i: Int, side: CGFloat) -> some View {
        let state = game.cells.indices.contains(i) ? game.cells[i] : .hidden
        let checker = ((i % game.cols) + (i / game.cols)) % 2 == 0
        ZStack {
            switch state {
            case .hidden, .flagged:
                RoundedRectangle(cornerRadius: side * 0.18, style: .continuous)
                    .fill(checker ? Color(hex: 0x3F8F6A) : Color(hex: 0x4AA37A))
                    .overlay(RoundedRectangle(cornerRadius: side * 0.18, style: .continuous).fill(.white.opacity(0.12)).padding(.bottom, side * 0.55))
                    .padding(side * 0.05)
                if state == .flagged {
                    Image(systemName: "flag.fill").font(.system(size: side * 0.48, weight: .bold)).foregroundStyle(Theme.coral)
                }
            case .open:
                Rectangle().fill(checker ? Color(hex: 0xE9DCC4) : Color(hex: 0xDFD0B4))
                if game.mine[i] {
                    Circle().fill(game.exploded == i ? Theme.stop : Color(hex: 0x1C1C28)).padding(side * 0.22)
                    Circle().fill(.white.opacity(0.6)).frame(width: side * 0.12).offset(x: -side * 0.08, y: -side * 0.08)
                } else if game.count[i] > 0 {
                    Text(verbatim: "\(game.count[i])")
                        .font(.system(size: side * 0.58, weight: .black, design: .rounded))
                        .foregroundStyle(Self.numberColors[game.count[i]])
                }
            }
        }
        .frame(width: side, height: side)
        .contentShape(Rectangle())
        .onTapGesture { game.tap(i) }
        .onLongPressGesture(minimumDuration: 0.35) { game.toggleFlag(i) }
        .accessibilityLabel(Text(verbatim: state == .open ? (game.mine[i] ? "💣" : "\(game.count[i])") : (state == .flagged ? "🚩" : "·")))
    }
}

struct MinesBackdrop: View {
    var body: some View {
        LinearGradient(colors: [Color(hex: 0x0D2B3E), Color(hex: 0x123A2E)], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}
