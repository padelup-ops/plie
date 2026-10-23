import SwiftUI
import Combine

extension Theme {
    static let draughts = Color(hex: 0xE07A5F)
}

// MARK: - Partie de dames (état de l'écran)

@Observable
final class DraughtsMatch {
    enum Phase: Equatable {
        case setup, playing
    }

    struct Saved: Codable {
        var moves: [String]
        var opponent: BoardOpponent
        var humanWhite: Bool
        var whiteSeat: Int
        var clock: ClockSetting
        var remaining: [Double]
    }

    struct Hop: Equatable {
        let id: Int
        let cell: Int
    }

    private(set) var phase: Phase = .setup
    private(set) var record = DraughtsGameRecord()
    private(set) var legal: [DraughtsMove] = DraughtsPosition.start.legalMoves()
    private(set) var opponent: BoardOpponent = .human
    private(set) var humanWhite = true
    private(set) var whiteSeat = 0
    let clock = BoardClock()
    /// Chemin en cours de saisie : case de départ, puis cases d'arrêt déjà choisies.
    private(set) var partial: [Int] = []
    private(set) var ids: [Int: Int] = [:]
    private(set) var hop: Hop?
    private(set) var fading: Set<Int> = []
    private(set) var busy = false
    /// Pièces prises par les Blancs (0) et par les Noirs (1) : true = dame.
    private(set) var captured: [[Bool]] = [[], []]
    private(set) var result: DraughtsResult?
    private(set) var request: BoardRequest?
    private(set) var thinking = false
    private(set) var paused = false
    private(set) var lastCaptureCount = 0
    var menuSide: Int?
    var resignSide: Int?

    @ObservationIgnored private var thinkToken = 0
    static let saveKey = "draughts.saved"

    var position: DraughtsPosition { record.position }
    var sideToMove: Int { position.whiteToMove ? 0 : 1 }
    var facing: Bool { !opponent.isComputer }
    var humanSide: Int { humanWhite ? 0 : 1 }
    var isHumanTurn: Bool { facing || sideToMove == humanSide }
    var mustCapture: Bool { !(legal.first?.captures.isEmpty ?? true) }

    func side(atSeat seat: Int) -> Int {
        if facing { return seat == whiteSeat ? 0 : 1 }
        return seat == 0 ? humanSide : 1 - humanSide
    }

    // MARK: Début, reprise, sauvegarde

    func start(opponent: BoardOpponent, clock setting: ClockSetting, humanWhite: Bool, swapSeats: Bool = false) {
        thinkToken += 1
        self.opponent = opponent
        self.humanWhite = humanWhite
        if swapSeats { whiteSeat = 1 - whiteSeat } else if phase == .setup { whiteSeat = 0 }
        record = DraughtsGameRecord()
        clock.reset(setting)
        resetTransient()
        rebuild()
        phase = .playing
        SoundPlayer.shared.play(.go, volume: 0.6)
        save()
        think()
    }

    func rematch() {
        start(opponent: opponent, clock: clock.setting, humanWhite: humanWhite, swapSeats: facing)
    }

    static var savedGame: Saved? {
        guard let data = UserDefaults.standard.data(forKey: saveKey) else { return nil }
        return try? JSONDecoder().decode(Saved.self, from: data)
    }

    func resume() {
        guard let s = Self.savedGame else { return }
        thinkToken += 1
        opponent = s.opponent
        humanWhite = s.humanWhite
        whiteSeat = s.whiteSeat
        record = DraughtsGameRecord(notations: s.moves)
        clock.restore(s.clock, remaining: s.remaining)
        resetTransient()
        rebuild()
        phase = .playing
        if clock.enabled && !record.moves.isEmpty { clock.running = sideToMove }
        think()
    }

    func save() {
        guard phase == .playing, result == nil else { return }
        let s = Saved(moves: record.moves.map(\.notation), opponent: opponent, humanWhite: humanWhite,
                      whiteSeat: whiteSeat, clock: clock.setting, remaining: clock.remaining)
        if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: Self.saveKey) }
    }

    func backToSetup() {
        thinkToken += 1
        thinking = false
        save()
        phase = .setup
    }

    private func clearSave() {
        UserDefaults.standard.removeObject(forKey: Self.saveKey)
    }

    private func resetTransient() {
        partial = []
        hop = nil
        fading = []
        busy = false
        result = nil
        request = nil
        thinking = false
        paused = false
        lastCaptureCount = 0
        menuSide = nil
        resignSide = nil
    }

    private func rebuild() {
        var map: [Int: Int] = [:]
        let start = DraughtsPosition.start
        for cell in DraughtsPosition.darkCells where start.board[cell] != 0 { map[cell] = cell }
        var taken: [[Bool]] = [[], []]
        var pos = start
        for m in record.moves {
            apply(m, to: &map, taken: &taken, position: pos)
            pos = pos.making(m)
        }
        ids = map
        captured = taken
        legal = position.legalMoves()
        lastCaptureCount = record.moves.last?.captures.count ?? 0
    }

    private func apply(_ m: DraughtsMove, to map: inout [Int: Int], taken: inout [[Bool]], position p: DraughtsPosition) {
        let mover = p.whiteToMove ? 0 : 1
        for c in m.captures {
            taken[mover].append(abs(p.board[c]) == 2)
            map[c] = nil
        }
        let id = map[m.from]
        map[m.from] = nil
        map[m.to] = id
    }

    // MARK: Jeu

    struct DisplayPiece: Identifiable, Equatable {
        let id: Int
        let cell: Int
        let value: Int8
        let fading: Bool
    }

    var pieces: [DisplayPiece] {
        ids.compactMap { cell, id in
            let v = position.board[cell]
            guard v != 0 else { return nil }
            let shown = hop?.id == id ? hop!.cell : cell
            return DisplayPiece(id: id, cell: shown, value: v, fading: fading.contains(cell))
        }
        .sorted { $0.id < $1.id }
    }

    var canInteract: Bool {
        phase == .playing && result == nil && !thinking && !paused && !busy && request == nil
            && resignSide == nil && menuSide == nil && isHumanTurn
    }

    /// Coups qui commencent par le chemin déjà choisi.
    var candidates: [DraughtsMove] {
        guard !partial.isEmpty else { return [] }
        return legal.filter { $0.path.count >= partial.count && Array($0.path.prefix(partial.count)) == partial }
    }

    /// Prochaines cases à toucher (étapes d'une rafle ou arrivée).
    var nextCells: Set<Int> {
        Set(candidates.compactMap { $0.path.count > partial.count ? $0.path[partial.count] : nil })
    }

    var finalCells: Set<Int> { Set(candidates.map(\.to)) }

    /// Pièces déjà sautées sur le chemin choisi (pour les montrer).
    var plannedCaptures: Set<Int> {
        guard partial.count > 1, let m = candidates.first else { return [] }
        return Set(m.captures.prefix(partial.count - 1))
    }

    /// Pièces qui peuvent jouer (et doivent prendre, s'il y a prise).
    var movablePieces: Set<Int> { Set(legal.map(\.from)) }

    private func signature(_ m: DraughtsMove) -> String { "\(m.to)-\(m.captures.sorted())" }

    func tap(_ cell: Int) {
        guard canInteract else { return }
        if !partial.isEmpty {
            let next = candidates.filter { $0.path.count > partial.count && $0.path[partial.count] == cell }
            if !next.isEmpty {
                if Set(next.map(signature)).count == 1 {
                    commit(next[0])
                } else {
                    partial.append(cell)
                    Haptics.tap()
                    SoundPlayer.shared.play(.notch, volume: 0.25)
                }
                return
            }
            let direct = candidates.filter { $0.to == cell }
            if !direct.isEmpty && Set(direct.map(signature)).count == 1 {
                commit(direct[0])
                return
            }
        }
        let v = position.board[cell]
        if v != 0 && (v > 0) == position.whiteToMove && movablePieces.contains(cell) && partial.first != cell {
            partial = [cell]
            Haptics.tap()
            SoundPlayer.shared.play(.notch, volume: 0.25)
        } else {
            if v != 0 && (v > 0) == position.whiteToMove && mustCapture && !movablePieces.contains(cell) {
                Haptics.warning()
            }
            partial = []
        }
    }

    private func commit(_ m: DraughtsMove) {
        partial = []
        let before = position
        let mover = sideToMove
        guard let id = ids[m.from] else { return }
        if m.captures.isEmpty {
            finalize(m, before: before, mover: mover)
            return
        }
        busy = true
        let step = 0.2
        for i in 1..<m.path.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + step * Double(i - 1)) { [weak self] in
                guard let self else { return }
                withAnimation(.easeInOut(duration: step * 0.9)) {
                    self.hop = Hop(id: id, cell: m.path[i])
                    if i - 1 < m.captures.count { self.fading.insert(m.captures[i - 1]) }
                }
                SoundPlayer.shared.play(.pieceCapture, volume: Float(min(1, 0.6 + 0.1 * Double(i))))
                Haptics.tap()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + step * Double(m.path.count - 1) + 0.08) { [weak self] in
            guard let self else { return }
            self.finalize(m, before: before, mover: mover)
        }
    }

    private func finalize(_ m: DraughtsMove, before: DraughtsPosition, mover: Int) {
        var map = ids
        var taken = captured
        apply(m, to: &map, taken: &taken, position: before)
        let promotes = before.promotes(m)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
            record.play(m)
            ids = map
            captured = taken
            hop = nil
            fading = []
        }
        busy = false
        legal = position.legalMoves()
        lastCaptureCount = m.captures.count
        clock.moved(by: mover)
        if m.captures.isEmpty { SoundPlayer.shared.play(.pieceMove, volume: 0.9) }
        if promotes { SoundPlayer.shared.play(.promote, volume: 0.85) }
        if let r = record.ruleResult {
            finish(r)
            return
        }
        save()
        think()
    }

    private func think() {
        guard phase == .playing, result == nil, opponent.isComputer, sideToMove != humanSide else { return }
        thinking = true
        thinkToken += 1
        let token = thinkToken
        let pos = position
        let level = opponent.level
        DispatchQueue.global(qos: .userInitiated).async {
            let started = Date()
            let move: DraughtsMove?
            switch level {
            case 1: move = DraughtsAI.bestMove(pos, maxDepth: 2, seconds: 0.4, noise: 70)
            case 2: move = DraughtsAI.bestMove(pos, maxDepth: 4, seconds: 1.0, noise: 12)
            default: move = DraughtsAI.bestMove(pos, maxDepth: 12, seconds: 2.2)
            }
            let wait = max(0, 0.7 - Date().timeIntervalSince(started))
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                guard let self, token == self.thinkToken, self.result == nil, self.phase == .playing else { return }
                self.thinking = false
                if let move { self.commit(move) }
            }
        }
    }

    #if DEBUG
    func debugDemo(solo: Bool) {
        start(opponent: solo ? .computer(level: 2) : .human, clock: solo ? .none : .five, humanWhite: true)
        for n in ["32-28", "19-23", "28x19", "14x23"] {
            if let m = position.legalMoves().first(where: { $0.notation == n }) { finalize(m, before: position, mover: sideToMove) }
        }
        thinkToken += 1
        thinking = false
        tap(DraughtsPosition.cell(ofNumber: 33))
    }
    #endif

    // MARK: Demandes

    func askUndo(side: Int) {
        guard phase == .playing, result == nil, !busy, !record.moves.isEmpty else { return }
        if facing {
            request = .undo(from: side)
        } else {
            thinkToken += 1
            thinking = false
            let count = sideToMove == humanSide ? 2 : 1
            guard record.moves.count >= count else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                record.undo(count)
                rebuild()
                partial = []
            }
            SoundPlayer.shared.play(.pieceMove, volume: 0.6)
            save()
            think()
        }
    }

    func offerDraw(side: Int) {
        guard phase == .playing, result == nil, facing else { return }
        request = .draw(from: side)
    }

    func answer(_ accept: Bool) {
        guard let r = request else { return }
        request = nil
        guard accept else {
            SoundPlayer.shared.play(.wrong, volume: 0.4)
            return
        }
        switch r {
        case .undo:
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                record.undo(1)
                rebuild()
                partial = []
            }
            if clock.enabled { clock.running = sideToMove }
            SoundPlayer.shared.play(.pieceMove, volume: 0.6)
            save()
        case .draw:
            finish(.agreement)
        }
    }

    func resign(side: Int) {
        resignSide = nil
        finish(.resignation(winnerWhite: side == 1))
    }

    func setResignPrompt(_ side: Int?) { resignSide = side }

    private func finish(_ r: DraughtsResult) {
        thinkToken += 1
        thinking = false
        result = r
        clock.running = nil
        partial = []
        clearSave()
        if r.winnerWhite != nil {
            SoundPlayer.shared.play(.win, volume: 0.85)
            Haptics.success()
        } else {
            SoundPlayer.shared.play(.vault, volume: 0.6)
        }
    }

    func tick(_ dt: Double) {
        guard phase == .playing, result == nil else { return }
        if let flagged = clock.tick(dt, paused: paused || request != nil || busy) {
            finish(.timeout(winnerWhite: flagged == 1))
        }
    }

    func setFolded(_ folded: Bool) {
        guard paused != folded else { return }
        paused = folded
        if phase == .playing && result == nil {
            SoundPlayer.shared.play(folded ? .stop : .go, volume: 0.4)
        }
    }

    // MARK: Textes

    func name(ofSide side: Int) -> String {
        if facing { return side == 0 ? L("Blancs") : L("Noirs") }
        return side == humanSide ? L("Toi") : L("Ordinateur · \(BoardOpponent.levelName(opponent.level))")
    }

    func status(ofSide side: Int) -> (String, Color) {
        let computer = !facing && side != humanSide
        if let r = result {
            let won = r.winnerWhite.map { ($0 ? 0 : 1) == side }
            switch r {
            case .win:
                if computer { return (won == true ? L("L'ordinateur gagne") : L("L'ordinateur est bloqué"), Theme.muted) }
                return won == true ? (L("Victoire ! L'adversaire ne peut plus jouer"), Theme.gold) : (L("Plus aucun coup possible"), Color(hex: 0xFF8A8A))
            case .timeout:
                return won == true ? (L("Victoire au temps"), Theme.gold) : (L("Temps écoulé"), Color(hex: 0xFF8A8A))
            case .resignation:
                return won == true ? (L("L'adversaire abandonne : victoire"), Theme.gold) : (L("Abandon"), Color(hex: 0xFF8A8A))
            case .repetition: return (L("Nulle par triple répétition"), Theme.muted)
            case .kingMoves: return (L("Nulle : 25 coups de dames sans prise"), Theme.muted)
            case .agreement: return (L("Nulle d'un commun accord"), Theme.muted)
            }
        }
        if paused { return (L("Pause : déplie le Duo pour reprendre"), Theme.muted) }
        if side == sideToMove {
            if computer { return (thinking ? L("Réfléchit…") : L("À son tour"), Theme.muted) }
            if mustCapture {
                let n = legal.first?.captures.count ?? 1
                return (n > 1 ? L("Prise obligatoire : rafle de \(n) pions !") : L("Prise obligatoire !"), Color(hex: 0xFFB35C))
            }
            return (L("À toi de jouer"), Theme.draughts)
        }
        if lastCaptureCount > 1 { return (L("Belle rafle : \(lastCaptureCount) pions pris"), Theme.muted) }
        return (L("En attente"), Theme.muted)
    }
}

// MARK: - Écran

struct DraughtsView: View {
    @Environment(AppState.self) private var app
    @Environment(StoreManager.self) private var store
    @State private var match = DraughtsMatch()
    @State private var hingePresent = false
    @State private var savedSummary: String?

    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { proxy in
            let layout = TableLayout(size: proxy.size, safe: proxy.safeAreaInsets, hingePresent: hingePresent, facing: match.facing)
            ZStack {
                if match.phase == .setup {
                    setup(safe: proxy.safeAreaInsets)
                } else {
                    table(layout)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .onAppear {
            refreshSaved()
            #if DEBUG
            if let demo = UserDefaults.standard.string(forKey: "boardDemo"), match.phase == .setup {
                match.debugDemo(solo: demo == "solo")
            }
            #endif
        }
        .onHingeAngle { degrees in
            hingePresent = degrees != nil
            guard let degrees else { return }
            if degrees < 150 { match.setFolded(true) } else if degrees > 165 { match.setFolded(false) }
        }
        .onReceive(ticker) { _ in match.tick(0.1) }
        .onChange(of: match.result) { _, r in
            guard let r else { return }
            app.recordBoardGame(chess: false, wonAgainstComputer: !match.facing && r.winnerWhite == match.humanWhite,
                                level: match.opponent.level)
        }
        .onDisappear { match.save() }
    }

    private func refreshSaved() {
        if let s = DraughtsMatch.savedGame {
            let n = (s.moves.count + 1) / 2
            savedSummary = s.opponent.isComputer ? L("\(n) coups contre l'ordinateur") : L("\(n) coups à deux")
        } else {
            savedSummary = nil
        }
    }

    private func setup(safe: EdgeInsets) -> some View {
        VStack(spacing: 6) {
            GameHeader(title: L("DAMES"), subtitle: L("Règles internationales, damier de 100 cases"), onBack: { app.route = .hub }) { EmptyView() }
                .padding(.horizontal, 16)
            ScrollView {
                BoardSetupCard(
                    title: L("Jeu de dames"),
                    symbolView: AnyView(DraughtsPieceView(white: true, king: true)),
                    accent: Theme.draughts,
                    rules: L("Touche un pion puis sa case d'arrivée. La prise est obligatoire, et il faut prendre le plus de pièces possible. Les pions prennent aussi en arrière, et les dames volent sur toute la diagonale."),
                    hingeHint: L("Déplie ton iPhone Duo et pose-le à plat entre vous : la charnière sépare vos deux camps. Replie-le un peu pour mettre la pendule en pause."),
                    savedSummary: savedSummary,
                    passLocked: { app.boardLevelNeedsPass($0, hasPass: store.ownsPass) },
                    onResume: { match.resume() },
                    onStart: { opponent, clock, white in match.start(opponent: opponent, clock: clock, humanWhite: white) },
                    onPass: { app.showPass = true }
                )
            }
        }
        .padding(.top, safe.top + 8)
        .padding(.bottom, safe.bottom)
        .padding(.leading, safe.leading)
        .padding(.trailing, safe.trailing)
    }

    private func table(_ layout: TableLayout) -> some View {
        let boardAngle: Double = match.facing ? layout.seatAngle(match.whiteSeat) : (match.humanWhite ? 0 : 180)
        return ZStack {
            DraughtsBoardView(match: match, side: layout.boardSide, boardAngle: boardAngle)
                .position(layout.center)
            ForEach(0..<2, id: \.self) { seat in
                SeatContainer(layout: layout, seat: seat) { size in
                    panel(seat: seat, size: size)
                }
            }
            if let r = match.result, r.winnerWhite != nil, match.facing || r.winnerWhite == match.humanWhite {
                ConfettiView()
                    .ignoresSafeArea()
            }
        }
    }

    private func panel(seat: Int, size: CGSize) -> some View {
        let side = match.side(atSeat: seat)
        let computer = !match.facing && side != match.humanSide
        let (status, statusColor) = match.status(ofSide: side)
        return SeatPanel(
            size: size,
            name: match.name(ofSide: side),
            status: status,
            statusColor: statusColor,
            isTurn: match.result == nil && match.sideToMove == side,
            accent: Theme.draughts,
            avatar: AnyView(Group {
                if computer {
                    Image(systemName: "cpu").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.draughts)
                } else {
                    DraughtsPieceView(white: side == 0, king: false).padding(3)
                }
            }),
            captured: AnyView(TakenDiscs(kings: match.captured[side], white: side == 1)),
            clock: match.clock.enabled ? (time: match.clock.remaining[side], active: match.clock.running == side && match.result == nil && !match.paused) : nil,
            actions: computer ? [] : actions(side: side),
            prompt: prompt(side: side, computer: computer)
        )
    }

    private func actions(side: Int) -> [SeatAction] {
        let playing = match.result == nil && !match.record.moves.isEmpty && !match.busy
        var list = [
            SeatAction(symbol: "arrow.uturn.backward", label: L("Reprendre un coup"), enabled: playing && !match.thinking) {
                match.askUndo(side: side)
            }
        ]
        if match.facing {
            list.append(SeatAction(symbol: "equal", label: L("Proposer la nulle"), enabled: playing) { match.offerDraw(side: side) })
        }
        list.append(SeatAction(symbol: "flag.fill", label: L("Abandonner"), enabled: match.result == nil) { match.setResignPrompt(side) })
        list.append(SeatAction(symbol: "ellipsis", label: L("Menu")) { match.menuSide = side })
        return list
    }

    private func prompt(side: Int, computer: Bool) -> SeatPrompt? {
        if computer { return nil }
        if let r = match.result {
            let (text, _) = match.status(ofSide: side)
            let won = r.winnerWhite.map { ($0 ? 0 : 1) == side }
            return SeatPrompt(
                message: won == true ? L("Bravo !") : (won == false ? L("Partie perdue") : L("Partie nulle")),
                detail: text,
                buttons: [
                    SeatPromptButton(title: match.facing ? L("Revanche") : L("Rejouer"), color: Theme.draughts) { match.rematch() },
                    SeatPromptButton(title: L("Menu"), color: Color.white.opacity(0.15), textColor: .white) { match.backToSetup(); refreshSaved() },
                ],
                extra: won == true ? AnyView(ShareResultButton(game: L("DAMES"), result: text, accent: Theme.draughts)) : nil
            )
        }
        if match.menuSide == side {
            return SeatPrompt(message: L("Menu"), detail: L("La partie est sauvegardée automatiquement."), buttons: [
                SeatPromptButton(title: L("Continuer"), color: Theme.draughts) { match.menuSide = nil },
                SeatPromptButton(title: L("Réglages"), color: Color.white.opacity(0.15), textColor: .white) { match.menuSide = nil; match.backToSetup(); refreshSaved() },
                SeatPromptButton(title: L("Accueil"), color: Color.white.opacity(0.15), textColor: .white) { match.menuSide = nil; match.save(); app.route = .hub },
            ])
        }
        if match.resignSide == side {
            return SeatPrompt(message: L("Abandonner la partie ?"), buttons: [
                SeatPromptButton(title: L("Abandonner"), color: Color(hex: 0xFF6B6B)) { match.resign(side: side) },
                SeatPromptButton(title: L("Non"), color: Color.white.opacity(0.15), textColor: .white) { match.setResignPrompt(nil) },
            ])
        }
        if let req = match.request {
            if req.from == side {
                return SeatPrompt(message: L("Demande envoyée"), detail: L("En attente de la réponse de l'adversaire…"))
            }
            let text: String
            switch req {
            case .undo: text = L("L'adversaire veut reprendre son coup")
            case .draw: text = L("L'adversaire propose la nulle")
            }
            return SeatPrompt(message: text, buttons: [
                SeatPromptButton(title: L("Accepter"), color: Theme.draughts) { match.answer(true) },
                SeatPromptButton(title: L("Refuser"), color: Color.white.opacity(0.15), textColor: .white) { match.answer(false) },
            ])
        }
        return nil
    }
}

/// Pions pris, empilés en petit.
struct TakenDiscs: View {
    let kings: [Bool]
    let white: Bool

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: -12) {
                ForEach(Array(kings.prefix(12).enumerated()), id: \.offset) { item in
                    DraughtsPieceView(white: white, king: item.element)
                        .frame(width: 24, height: 24)
                }
            }
            if !kings.isEmpty {
                Text("× \(kings.count)")
                    .font(.plie(13, weight: .bold))
                    .foregroundStyle(Theme.draughts)
            }
        }
        .frame(height: 26)
        .animation(.easeOut(duration: 0.2), value: kings.count)
    }
}

// MARK: - Damier

struct DraughtsBoardView: View {
    let match: DraughtsMatch
    let side: CGFloat
    let boardAngle: Double

    var body: some View {
        let frame = side * 0.05
        let q = (side - 2 * frame) / 10
        let facing = match.facing
        ZStack(alignment: .topLeading) {
            DraughtsBoardCanvas()
            DraughtsHighlights(match: match, frame: frame, q: q)
            ForEach(match.pieces) { piece in
                let white = piece.value > 0
                let angle = facing ? (white ? 0 : 180) : -boardAngle
                DraughtsPieceView(white: white, king: abs(piece.value) == 2, lifted: match.partial.first == piece.cell || match.hop?.id == piece.id)
                    .frame(width: q * 0.96, height: q * 0.96)
                    .rotationEffect(.degrees(angle))
                    .opacity(piece.fading ? 0.35 : 1)
                    .position(DraughtsBoardView.center(piece.cell, frame: frame, q: q))
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
            ForEach(DraughtsPosition.darkCells, id: \.self) { cell in
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: q, height: q)
                    .position(DraughtsBoardView.center(cell, frame: frame, q: q))
                    .onTapGesture { match.tap(cell) }
            }
        }
        .frame(width: side, height: side)
        .rotationEffect(.degrees(boardAngle))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Damier"))
    }

    static func center(_ cell: Int, frame: CGFloat, q: CGFloat) -> CGPoint {
        CGPoint(x: frame + (CGFloat(cell % 10) + 0.5) * q, y: frame + (CGFloat(cell / 10) + 0.5) * q)
    }
}

/// Damier : marbre crème et acajou, cadre laqué noir, filet de laiton.
struct DraughtsBoardCanvas: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let frame = s * 0.05
            let inner = s - 2 * frame
            let q = inner / 10
            let outer = Path(roundedRect: CGRect(x: 0, y: 0, width: s, height: s), cornerRadius: s * 0.03)
            context.drawLayer { shadow in
                shadow.addFilter(.blur(radius: s * 0.025))
                shadow.fill(outer.offsetBy(dx: s * 0.008, dy: s * 0.025), with: .color(.black.opacity(0.55)))
            }
            context.fill(outer, with: .linearGradient(Gradient(colors: [Color(hex: 0x34343C), Color(hex: 0x16161A), Color(hex: 0x0B0B0D)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: s, y: s)))
            context.stroke(Path(roundedRect: CGRect(x: 1.5, y: 1.5, width: s - 3, height: s - 3), cornerRadius: s * 0.03),
                           with: .color(.white.opacity(0.15)), lineWidth: 2)
            for row in 0..<10 {
                for col in 0..<10 {
                    let rect = CGRect(x: frame + CGFloat(col) * q, y: frame + CGFloat(row) * q, width: q + 0.4, height: q + 0.4)
                    let dark = (row + col) % 2 == 1
                    context.fill(Path(rect), with: .linearGradient(
                        Gradient(colors: dark ? [Color(hex: 0x7A3424), Color(hex: 0x4E1D13)] : [Color(hex: 0xF6EDDB), Color(hex: 0xE6D6B8)]),
                        startPoint: rect.origin, endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
                    var cell = context
                    cell.clip(to: Path(rect))
                    if dark {
                        Wood.grain(&cell, rect: rect, horizontal: false, seed: row * 10 + col, color: Color(hex: 0x2A0E08), opacity: 0.32)
                    } else {
                        Wood.marble(&cell, rect: rect, seed: row * 10 + col, color: Color(hex: 0x9C8F7A).opacity(0.28))
                    }
                }
            }
            let board = CGRect(x: frame, y: frame, width: inner, height: inner)
            context.fill(Path(board), with: .linearGradient(Gradient(colors: [.white.opacity(0.14), .clear, .black.opacity(0.12)]),
                                                           startPoint: board.origin, endPoint: CGPoint(x: board.maxX, y: board.maxY)))
            context.stroke(Path(board.insetBy(dx: -4, dy: -4)), with: .color(Color(hex: 0xC8A35A)), lineWidth: 2)
        }
        .accessibilityHidden(true)
    }
}

struct DraughtsHighlights: View {
    let match: DraughtsMatch
    let frame: CGFloat
    let q: CGFloat

    var body: some View {
        let last = match.record.moves.last
        let selected = match.partial
        let next = match.nextCells
        let finals = match.finalCells
        let planned = match.plannedCaptures
        let mustCapture = match.mustCapture && match.canInteract && selected.isEmpty
        let movable = match.movablePieces
        let interactive = match.canInteract
        Canvas { context, _ in
            func rect(_ cell: Int) -> CGRect {
                CGRect(x: frame + CGFloat(cell % 10) * q, y: frame + CGFloat(cell / 10) * q, width: q, height: q)
            }
            if let last {
                for cell in [last.from, last.to] {
                    context.fill(Path(rect(cell)), with: .color(Color(hex: 0xF6D365).opacity(0.28)))
                }
            }
            if mustCapture {
                for cell in movable {
                    let r = rect(cell).insetBy(dx: q * 0.02, dy: q * 0.02)
                    context.stroke(Path(roundedRect: r, cornerRadius: q * 0.12), with: .color(Color(hex: 0xFFB35C).opacity(0.9)), lineWidth: 3)
                }
            }
            if let first = selected.first {
                context.fill(Path(rect(first)), with: .color(Color(hex: 0xF6D365).opacity(0.45)))
                // Chemin déjà choisi
                if selected.count > 1 {
                    var trail = Path()
                    for (i, cell) in selected.enumerated() {
                        let r = rect(cell)
                        let p = CGPoint(x: r.midX, y: r.midY)
                        if i == 0 { trail.move(to: p) } else { trail.addLine(to: p) }
                    }
                    context.stroke(trail, with: .color(Color(hex: 0xFFE9A8).opacity(0.85)), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [8, 6]))
                }
            }
            for cell in planned {
                let r = rect(cell).insetBy(dx: q * 0.08, dy: q * 0.08)
                context.stroke(Path(ellipseIn: r), with: .color(Color(hex: 0xFF5C4D).opacity(0.9)), lineWidth: 3)
            }
            if interactive {
                for cell in next.union(finals) {
                    let r = rect(cell)
                    if finals.contains(cell) {
                        let d = q * 0.18
                        context.fill(Path(ellipseIn: CGRect(x: r.midX - d, y: r.midY - d, width: d * 2, height: d * 2)),
                                     with: .color(Color(hex: 0xFFE9A8).opacity(0.8)))
                    } else {
                        context.stroke(Path(ellipseIn: r.insetBy(dx: q * 0.22, dy: q * 0.22)),
                                       with: .color(Color(hex: 0xFFE9A8).opacity(0.8)), lineWidth: 3)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
