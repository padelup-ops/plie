import SwiftUI
import Combine

extension Theme {
    static let chess = Color(hex: 0xE3B66E)
}

// MARK: - Partie d'échecs (état de l'écran)

@Observable
final class ChessMatch {
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

    private(set) var phase: Phase = .setup
    private(set) var record = ChessGameRecord()
    private(set) var opponent: BoardOpponent = .human
    private(set) var humanWhite = true
    /// En face à face : le siège (0 en bas ou à gauche, 1 en face) des Blancs. Il change à chaque revanche.
    private(set) var whiteSeat = 0
    let clock = BoardClock()
    private(set) var selected: Int?
    private(set) var targets: [ChessMove] = []
    private(set) var ids: [Int: Int] = [:]
    /// Pièces prises par les Blancs (0) et par les Noirs (1).
    private(set) var captured: [[Int8]] = [[], []]
    private(set) var result: ChessResult?
    private(set) var request: BoardRequest?
    private(set) var promotionChoices: [ChessMove] = []
    private(set) var thinking = false
    private(set) var paused = false
    private(set) var lastSAN: String?
    var menuSide: Int?
    var resignSide: Int?

    @ObservationIgnored private var thinkToken = 0
    static let saveKey = "chess.saved"

    var position: ChessPosition { record.position }
    var sideToMove: Int { position.whiteToMove ? 0 : 1 }
    var facing: Bool { !opponent.isComputer }
    var humanSide: Int { humanWhite ? 0 : 1 }
    var isHumanTurn: Bool { facing || sideToMove == humanSide }

    /// Camp assis à un siège donné.
    func side(atSeat seat: Int) -> Int {
        if facing { return seat == whiteSeat ? 0 : 1 }
        return seat == 0 ? humanSide : 1 - humanSide
    }

    var letters: [String] {
        Lang.shared.isEnglish ? ["N", "B", "R", "Q", "K"] : ["C", "F", "T", "D", "R"]
    }

    // MARK: Début, reprise, sauvegarde

    func start(opponent: BoardOpponent, clock setting: ClockSetting, humanWhite: Bool, swapSeats: Bool = false) {
        thinkToken += 1
        self.opponent = opponent
        self.humanWhite = humanWhite
        if swapSeats { whiteSeat = 1 - whiteSeat } else if !swapSeats && phase == .setup { whiteSeat = 0 }
        record = ChessGameRecord()
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
        record = ChessGameRecord(uciMoves: s.moves)
        clock.restore(s.clock, remaining: s.remaining)
        resetTransient()
        rebuild()
        phase = .playing
        if clock.enabled && !record.moves.isEmpty { clock.running = sideToMove }
        think()
    }

    func save() {
        guard phase == .playing, result == nil else { return }
        let s = Saved(moves: record.moves.map(\.uci), opponent: opponent, humanWhite: humanWhite,
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
        selected = nil
        targets = []
        result = nil
        request = nil
        promotionChoices = []
        thinking = false
        paused = false
        lastSAN = nil
        menuSide = nil
        resignSide = nil
    }

    /// Recalcule les identifiants des pièces (pour les animations) et les prises, en rejouant la partie.
    private func rebuild() {
        var map: [Int: Int] = [:]
        let start = ChessPosition.start
        for sq in 0..<64 where start.board[sq] != 0 { map[sq] = sq }
        var taken: [[Int8]] = [[], []]
        var pos = start
        for m in record.moves {
            apply(m, to: &map, taken: &taken, position: pos)
            pos = pos.making(m)
        }
        ids = map
        captured = taken
        lastSAN = nil
        if let last = record.moves.last, record.positions.count >= 2 {
            lastSAN = record.positions[record.positions.count - 2].san(last, letters: letters)
        }
    }

    private func apply(_ m: ChessMove, to map: inout [Int: Int], taken: inout [[Int8]], position p: ChessPosition) {
        let mover = p.whiteToMove ? 0 : 1
        if m.isEnPassant {
            let victim = m.to + (p.whiteToMove ? -8 : 8)
            map[victim] = nil
            taken[mover].append(ChessPiece.pawn)
        } else if p.board[m.to] != 0 {
            map[m.to] = nil
            taken[mover].append(abs(p.board[m.to]))
        }
        map[m.to] = map[m.from]
        map[m.from] = nil
        if m.isCastle {
            let (rf, rt) = m.to > m.from ? (m.from + 3, m.from + 1) : (m.from - 4, m.from - 1)
            map[rt] = map[rf]
            map[rf] = nil
        }
    }

    // MARK: Jeu

    struct DisplayPiece: Identifiable, Equatable {
        let id: Int
        let square: Int
        let value: Int8
    }

    var pieces: [DisplayPiece] {
        ids.compactMap { sq, id in
            let v = position.board[sq]
            return v == 0 ? nil : DisplayPiece(id: id, square: sq, value: v)
        }
        .sorted { $0.id < $1.id }
    }

    var canInteract: Bool {
        phase == .playing && result == nil && !thinking && !paused && request == nil
            && promotionChoices.isEmpty && resignSide == nil && menuSide == nil && isHumanTurn
    }

    func tap(_ sq: Int) {
        guard canInteract else { return }
        if selected != nil {
            let moves = targets.filter { $0.to == sq }
            if moves.count > 1 {
                promotionChoices = moves
                return
            }
            if let m = moves.first {
                commit(m)
                return
            }
        }
        let v = position.board[sq]
        if v != 0 && (v > 0) == position.whiteToMove && sq != selected {
            selected = sq
            targets = position.legalMoves().filter { $0.from == sq }
            Haptics.tap()
            SoundPlayer.shared.play(.notch, volume: 0.25)
        } else {
            selected = nil
            targets = []
        }
    }

    func choosePromotion(_ m: ChessMove?) {
        promotionChoices = []
        if let m { commit(m) }
    }

    private func commit(_ m: ChessMove) {
        let before = position
        let mover = sideToMove
        let san = before.san(m, letters: letters)
        var map = ids
        var taken = captured
        apply(m, to: &map, taken: &taken, position: before)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            record.play(m)
            ids = map
            captured = taken
            selected = nil
            targets = []
        }
        lastSAN = san
        clock.moved(by: mover)
        // Sons : bois posé, prise, roque, promotion, échec
        if m.isCapture {
            SoundPlayer.shared.play(.pieceCapture, volume: 0.9)
        } else {
            SoundPlayer.shared.play(.pieceMove, volume: 0.9)
        }
        if m.isCastle {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { SoundPlayer.shared.play(.pieceMove, volume: 0.7) }
        }
        if m.promotion != 0 { SoundPlayer.shared.play(.promote, volume: 0.8) }
        Haptics.tap()
        if let r = record.ruleResult {
            finish(r)
            return
        }
        if position.sideInCheck {
            SoundPlayer.shared.play(.checkBell, volume: 0.7)
            Haptics.warning()
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
            let move: ChessMove?
            switch level {
            case 1: move = ChessAI.bestMove(pos, maxDepth: 1, seconds: 0.4, noise: 150)
            case 2: move = ChessAI.bestMove(pos, maxDepth: 2, seconds: 1.0, noise: 30)
            default: move = ChessAI.bestMove(pos, maxDepth: 6, seconds: 2.2)
            }
            let wait = max(0, 0.7 - Date().timeIntervalSince(started))
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                guard let self, token == self.thinkToken, self.result == nil, self.phase == .playing else { return }
                self.thinking = false
                if let move { self.commit(move) }
            }
        }
    }

    // MARK: Demandes entre joueurs

    func askUndo(side: Int) {
        guard phase == .playing, result == nil, !record.moves.isEmpty else { return }
        if facing {
            request = .undo(from: side)
        } else {
            // Contre l'ordinateur : on reprend son propre dernier coup (et la réponse de l'ordinateur).
            thinkToken += 1
            thinking = false
            let count = sideToMove == humanSide ? 2 : 1
            guard record.moves.count >= count else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                record.undo(count)
                rebuild()
                selected = nil
                targets = []
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
                selected = nil
                targets = []
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

    private func finish(_ r: ChessResult) {
        thinkToken += 1
        thinking = false
        result = r
        clock.running = nil
        selected = nil
        targets = []
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
        if let flagged = clock.tick(dt, paused: paused || request != nil) {
            let winnerWhite = flagged == 1
            finish(position.hasMatingMaterial(white: winnerWhite) ? .timeout(winnerWhite: winnerWhite) : .timeoutDraw)
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
            case .checkmate:
                if computer { return (won == true ? L("Échec et mat : l'ordinateur gagne") : L("Échec et mat : l'ordinateur perd"), Theme.muted) }
                return won == true ? (L("Échec et mat ! Victoire"), Theme.gold) : (L("Échec et mat"), Color(hex: 0xFF8A8A))
            case .timeout:
                return won == true ? (L("Victoire au temps"), Theme.gold) : (L("Temps écoulé"), Color(hex: 0xFF8A8A))
            case .resignation:
                return won == true ? (L("L'adversaire abandonne : victoire"), Theme.gold) : (L("Abandon"), Color(hex: 0xFF8A8A))
            case .stalemate: return (L("Pat : partie nulle"), Theme.muted)
            case .fiftyMoves: return (L("Nulle : 50 coups sans prise ni pion"), Theme.muted)
            case .repetition: return (L("Nulle par triple répétition"), Theme.muted)
            case .insufficient: return (L("Nulle : plus de quoi mater"), Theme.muted)
            case .timeoutDraw: return (L("Temps écoulé : nulle, plus de quoi mater"), Theme.muted)
            case .agreement: return (L("Nulle d'un commun accord"), Theme.muted)
            }
        }
        if paused { return (L("Pause : déplie le Duo pour reprendre"), Theme.muted) }
        if side == sideToMove {
            if computer { return (thinking ? L("Réfléchit…") : L("À son tour"), Theme.muted) }
            if position.sideInCheck { return (L("Échec ! À toi de jouer"), Color(hex: 0xFF8A8A)) }
            return (L("À toi de jouer"), Theme.chess)
        }
        if let san = lastSAN, side != sideToMove { return (L("Dernier coup : \(san)"), Theme.muted) }
        return (L("En attente"), Theme.muted)
    }
}

// MARK: - Écran

struct ChessView: View {
    @Environment(AppState.self) private var app
    @Environment(StoreManager.self) private var store
    @State private var match = ChessMatch()
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
        .onAppear { refreshSaved() }
        .onHingeAngle { degrees in
            hingePresent = degrees != nil
            guard let degrees else { return }
            if degrees < 150 { match.setFolded(true) } else if degrees > 165 { match.setFolded(false) }
        }
        .onReceive(ticker) { _ in match.tick(0.1) }
        .onChange(of: match.result) { _, r in
            guard let r else { return }
            app.recordBoardGame(chess: true, wonAgainstComputer: !match.facing && r.winnerWhite == (match.humanWhite),
                                level: match.opponent.level)
        }
        .onDisappear { match.save() }
    }

    private func refreshSaved() {
        if let s = ChessMatch.savedGame {
            let n = (s.moves.count + 1) / 2
            savedSummary = s.opponent.isComputer ? L("\(n) coups contre l'ordinateur") : L("\(n) coups à deux")
        } else {
            savedSummary = nil
        }
    }

    // MARK: Réglages

    private func setup(safe: EdgeInsets) -> some View {
        VStack(spacing: 6) {
            GameHeader(title: L("ÉCHECS"), subtitle: L("Face à face sur le Duo déplié"), onBack: { app.route = .hub }) { EmptyView() }
                .padding(.horizontal, 16)
            ScrollView {
                BoardSetupCard(
                    title: L("Échecs"),
                    symbolView: AnyView(ChessPieceView(type: ChessPiece.knight, white: true)),
                    accent: Theme.chess,
                    rules: L("Touche une pièce pour voir ses coups, puis touche la case d'arrivée. Toutes les règles sont là : roque, prise en passant, promotion, pat et nulles."),
                    hingeHint: L("Déplie ton iPhone Duo et pose-le à plat entre vous : la charnière sépare vos deux camps, chacun voit ses pièces à l'endroit. Replie-le un peu pour mettre la pendule en pause."),
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

    // MARK: Table de jeu

    private func table(_ layout: TableLayout) -> some View {
        let boardAngle: Double = match.facing ? layout.seatAngle(match.whiteSeat) : (match.humanWhite ? 0 : 180)
        return ZStack {
            ChessBoardView(match: match, side: layout.boardSide, boardAngle: boardAngle)
                .position(layout.center)

            ForEach(0..<2, id: \.self) { seat in
                SeatContainer(layout: layout, seat: seat) { size in
                    panel(seat: seat, size: size)
                }
            }

            if !match.promotionChoices.isEmpty {
                let seat = seatOf(side: match.sideToMove)
                promotionPicker
                    .rotationEffect(.degrees(layout.seatAngle(seat)))
                    .position(layout.center)
            }

            if let r = match.result, r.winnerWhite != nil, match.facing || r.winnerWhite == match.humanWhite {
                ConfettiView()
                    .ignoresSafeArea()
            }
        }
    }

    private func seatOf(side: Int) -> Int {
        (0..<2).first { match.side(atSeat: $0) == side } ?? 0
    }

    private var promotionPicker: some View {
        let white = match.position.whiteToMove
        return VStack(spacing: 10) {
            Text(L("Promotion : choisis ta pièce"))
                .font(.plie(16, weight: .bold))
                .foregroundStyle(.white)
            HStack(spacing: 10) {
                ForEach(match.promotionChoices, id: \.self) { m in
                    Button { match.choosePromotion(m) } label: {
                        ChessPieceView(type: m.promotion, white: white)
                            .frame(width: 58, height: 58)
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            Button(L("Annuler")) { match.choosePromotion(nil) }
                .font(.plie(14, weight: .bold))
                .foregroundStyle(Theme.muted)
        }
        .padding(18)
        .winCard(accent: Theme.chess)
    }

    private func panel(seat: Int, size: CGSize) -> some View {
        let side = match.side(atSeat: seat)
        let computer = !match.facing && side != match.humanSide
        let (status, statusColor) = match.status(ofSide: side)
        let opponentSide = 1 - side
        return SeatPanel(
            size: size,
            name: match.name(ofSide: side),
            status: status,
            statusColor: statusColor,
            isTurn: match.result == nil && match.sideToMove == side,
            accent: Theme.chess,
            avatar: AnyView(Group {
                if computer {
                    Image(systemName: "cpu").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.chess)
                } else {
                    ChessPieceView(type: ChessPiece.king, white: side == 0).padding(4)
                }
            }),
            captured: AnyView(CapturedStrip(types: match.captured[side], white: side == 1, opponent: match.captured[opponentSide])),
            clock: match.clock.enabled ? (time: match.clock.remaining[side], active: match.clock.running == side && match.result == nil && !match.paused) : nil,
            actions: computer ? [] : actions(side: side),
            prompt: prompt(side: side, computer: computer)
        )
    }

    private func actions(side: Int) -> [SeatAction] {
        let playing = match.result == nil && !match.record.moves.isEmpty
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
                    SeatPromptButton(title: match.facing ? L("Revanche") : L("Rejouer"), color: Theme.chess) { match.rematch() },
                    SeatPromptButton(title: L("Menu"), color: Color.white.opacity(0.15), textColor: .white) { match.backToSetup(); refreshSaved() },
                ]
            )
        }
        if match.menuSide == side {
            return SeatPrompt(message: L("Menu"), detail: L("La partie est sauvegardée automatiquement."), buttons: [
                SeatPromptButton(title: L("Continuer"), color: Theme.chess) { match.menuSide = nil },
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
                SeatPromptButton(title: L("Accepter"), color: Theme.chess) { match.answer(true) },
                SeatPromptButton(title: L("Refuser"), color: Color.white.opacity(0.15), textColor: .white) { match.answer(false) },
            ])
        }
        return nil
    }
}

/// Pièces prises, en petit, avec l'avance de matériel.
struct CapturedStrip: View {
    let types: [Int8]
    let white: Bool
    let opponent: [Int8]

    var body: some View {
        let values: [Int8: Int] = [1: 1, 2: 3, 3: 3, 4: 5, 5: 9]
        let mine = types.reduce(0) { $0 + (values[$1] ?? 0) }
        let theirs = opponent.reduce(0) { $0 + (values[$1] ?? 0) }
        HStack(spacing: -6) {
            ForEach(Array(types.sorted(by: >).enumerated()), id: \.offset) { item in
                ChessPieceView(type: item.element, white: white)
                    .frame(width: 22, height: 22)
            }
            if mine > theirs {
                Text("+\(mine - theirs)")
                    .font(.plie(13, weight: .bold))
                    .foregroundStyle(Theme.chess)
                    .padding(.leading, 10)
            }
        }
        .frame(height: 24)
        .animation(.easeOut(duration: 0.2), value: types.count)
    }
}

// MARK: - Plateau

struct ChessBoardView: View {
    let match: ChessMatch
    let side: CGFloat
    let boardAngle: Double

    var body: some View {
        let frame = side * 0.06
        let q = (side - 2 * frame) / 8
        let facing = match.facing
        ZStack(alignment: .topLeading) {
            ChessBoardCanvas()
            ChessHighlights(match: match, frame: frame, q: q)
            ForEach(match.pieces) { piece in
                let center = ChessBoardView.center(piece.square, frame: frame, q: q)
                let white = piece.value > 0
                let angle = facing ? (white ? 0 : 180) : -boardAngle
                ChessPieceView(type: abs(piece.value), white: white, lifted: match.selected == piece.square)
                    .frame(width: q * 0.92, height: q * 0.92)
                    .rotationEffect(.degrees(angle))
                    .position(center)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
            ForEach(0..<64, id: \.self) { sq in
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: q, height: q)
                    .position(ChessBoardView.center(sq, frame: frame, q: q))
                    .onTapGesture { match.tap(sq) }
            }
        }
        .frame(width: side, height: side)
        .rotationEffect(.degrees(boardAngle))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Échiquier"))
    }

    static func center(_ sq: Int, frame: CGFloat, q: CGFloat) -> CGPoint {
        CGPoint(x: frame + (CGFloat(ChessPosition.file(sq)) + 0.5) * q,
                y: frame + (7 - CGFloat(ChessPosition.rank(sq)) + 0.5) * q)
    }
}

/// Échiquier en marqueterie : érable et noyer, cadre en palissandre, filet doré, coordonnées.
struct ChessBoardCanvas: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let frame = s * 0.06
            let inner = s - 2 * frame
            let q = inner / 8
            let outer = Path(roundedRect: CGRect(x: 0, y: 0, width: s, height: s), cornerRadius: s * 0.03)
            context.drawLayer { shadow in
                shadow.addFilter(.blur(radius: s * 0.025))
                shadow.fill(outer.offsetBy(dx: s * 0.008, dy: s * 0.025), with: .color(.black.opacity(0.55)))
            }
            context.fill(outer, with: .linearGradient(Gradient(colors: [Color(hex: 0x6B3E22), Color(hex: 0x4A2614), Color(hex: 0x2E160B)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: s, y: s)))
            Wood.grain(&context, rect: CGRect(x: 0, y: 0, width: s, height: s), horizontal: true, seed: 999, color: .black, opacity: 0.12)
            context.stroke(Path(roundedRect: CGRect(x: 1.5, y: 1.5, width: s - 3, height: s - 3), cornerRadius: s * 0.03),
                           with: .color(.white.opacity(0.18)), lineWidth: 2)
            for rank in 0..<8 {
                for file in 0..<8 {
                    let rect = CGRect(x: frame + CGFloat(file) * q, y: frame + CGFloat(7 - rank) * q, width: q + 0.4, height: q + 0.4)
                    let light = (rank + file) % 2 == 1
                    context.fill(Path(rect), with: .linearGradient(
                        Gradient(colors: light ? [Color(hex: 0xF0D7AC), Color(hex: 0xDDB988)] : [Color(hex: 0x9A6440), Color(hex: 0x76472B)]),
                        startPoint: rect.origin, endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
                    var cell = context
                    cell.clip(to: Path(rect))
                    Wood.grain(&cell, rect: rect, horizontal: light, seed: rank * 8 + file,
                               color: light ? Color(hex: 0x8A5A30) : Color(hex: 0x3E2010), opacity: light ? 0.15 : 0.3)
                }
            }
            let board = CGRect(x: frame, y: frame, width: inner, height: inner)
            context.fill(Path(board), with: .linearGradient(Gradient(colors: [.white.opacity(0.16), .clear, .black.opacity(0.14)]),
                                                           startPoint: board.origin, endPoint: CGPoint(x: board.maxX, y: board.maxY)))
            context.stroke(Path(board.insetBy(dx: -3, dy: -3)), with: .color(Color(hex: 0xD9B26A).opacity(0.85)), lineWidth: 1.6)
            // Coordonnées : à l'endroit pour les Blancs (bas, gauche) et pour les Noirs (haut, droite)
            let font = Font.system(size: frame * 0.42, weight: .semibold, design: .serif)
            let gold = Color(hex: 0xE2C189)
            for i in 0..<8 {
                let file = String(Array("abcdefgh")[i])
                let cx = frame + (CGFloat(i) + 0.5) * q
                context.draw(Text(file).font(font).foregroundColor(gold), at: CGPoint(x: cx, y: s - frame * 0.5))
                var top = context
                top.translateBy(x: cx, y: frame * 0.5)
                top.rotate(by: .degrees(180))
                top.draw(Text(file).font(font).foregroundColor(gold), at: .zero)
                let cy = frame + (7 - CGFloat(i) + 0.5) * q
                context.draw(Text("\(i + 1)").font(font).foregroundColor(gold), at: CGPoint(x: frame * 0.5, y: cy))
                var right = context
                right.translateBy(x: s - frame * 0.5, y: cy)
                right.rotate(by: .degrees(180))
                right.draw(Text("\(i + 1)").font(font).foregroundColor(gold), at: .zero)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Dernier coup, pièce choisie, cases possibles, roi en échec.
struct ChessHighlights: View {
    let match: ChessMatch
    let frame: CGFloat
    let q: CGFloat

    var body: some View {
        let last = match.record.moves.last
        let selected = match.selected
        let targets = match.targets
        let checkSquare: Int? = match.position.sideInCheck ? match.position.kingSquare(white: match.position.whiteToMove) : nil
        let interactive = match.canInteract
        Canvas { context, _ in
            func rect(_ sq: Int) -> CGRect {
                CGRect(x: frame + CGFloat(ChessPosition.file(sq)) * q, y: frame + CGFloat(7 - ChessPosition.rank(sq)) * q, width: q, height: q)
            }
            if let last {
                for sq in [last.from, last.to] {
                    context.fill(Path(rect(sq)), with: .color(Color(hex: 0xF6D365).opacity(0.36)))
                }
            }
            if let checkSquare {
                let r = rect(checkSquare)
                context.fill(Path(ellipseIn: r.insetBy(dx: -q * 0.1, dy: -q * 0.1)),
                             with: .radialGradient(Gradient(colors: [Color(hex: 0xFF3B30).opacity(0.9), Color(hex: 0xFF3B30).opacity(0)]),
                                                   center: CGPoint(x: r.midX, y: r.midY), startRadius: 0, endRadius: q * 0.62))
            }
            if let selected {
                let r = rect(selected)
                context.fill(Path(r), with: .color(Color(hex: 0xF6D365).opacity(0.5)))
                context.stroke(Path(r.insetBy(dx: 2, dy: 2)), with: .color(Color(hex: 0xFFE9A8).opacity(0.9)), lineWidth: 3)
            }
            if interactive {
                for m in targets {
                    let r = rect(m.to)
                    if m.isCapture {
                        context.stroke(Path(ellipseIn: r.insetBy(dx: q * 0.07, dy: q * 0.07)),
                                       with: .color(Color(hex: 0x1A1008).opacity(0.38)), lineWidth: q * 0.08)
                    } else {
                        let d = q * 0.17
                        context.fill(Path(ellipseIn: CGRect(x: r.midX - d, y: r.midY - d, width: d * 2, height: d * 2)),
                                     with: .color(Color(hex: 0x1A1008).opacity(0.32)))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
