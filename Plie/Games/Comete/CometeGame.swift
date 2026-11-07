import SwiftUI

extension Theme {
    static let comete = Color(hex: 0x7B5CFF)
}

// MARK: - COMÈTE, le shoot'em up
//
// Le Duo ouvert en long : ton vaisseau en bas, les vagues d'ennemis arrivent d'en haut
// et traversent la charnière. On glisse le doigt n'importe où pour piloter, le tir est automatique.
// Plie le Duo à moitié (puis rouvre-le) : une bombe nettoie l'écran.
// Tout se calcule en pixels de l'image (128 de large).

@Observable
final class CometeGame {
    enum Phase: Equatable { case menu, playing, over }
    enum Kind: Int { case drone, zigzag, shooter, tank, boss }

    struct Enemy {
        var kind: Kind
        var x: Double, y: Double, vx: Double, vy: Double
        var hp: Int
        var maxHP: Int
        var t: Double = 0
        var fire: Double = 1.5
        var flash: Double = 0
    }

    struct Shot { var x: Double, y: Double, vx: Double, vy: Double }

    struct Bonus {
        enum Kind { case power, shield, bomb }
        var kind: Kind
        var x: Double, y: Double
    }

    struct Spark { var x: Double, y: Double, vx: Double, vy: Double, life: Double, color: UInt32 }

    private(set) var phase: Phase = .menu
    private(set) var frame = 0
    private(set) var score = 0
    private(set) var best: Int
    private(set) var lives = 3
    private(set) var bombs = 2
    private(set) var wave = 0
    private(set) var banner: String?
    private(set) var bossHP: Double?

    @ObservationIgnored let cols = 128
    @ObservationIgnored private(set) var rows = 280
    @ObservationIgnored private(set) var bottomLimit: Double = 250
    @ObservationIgnored private(set) var topLimit: Double = 30
    @ObservationIgnored private(set) var time: Double = 0
    @ObservationIgnored private(set) var shipX: Double = 64
    @ObservationIgnored private(set) var shipY: Double = 230
    @ObservationIgnored private(set) var enemies: [Enemy] = []
    @ObservationIgnored private(set) var shots: [Shot] = []
    @ObservationIgnored private(set) var enemyShots: [Shot] = []
    @ObservationIgnored private(set) var bonuses: [Bonus] = []
    @ObservationIgnored private(set) var sparks: [Spark] = []
    @ObservationIgnored private(set) var shake: Double = 0
    @ObservationIgnored private(set) var bombFlash: Double = 0
    @ObservationIgnored private(set) var invincible: Double = 0
    @ObservationIgnored private(set) var shield: Double = 0
    @ObservationIgnored private(set) var power = 1
    @ObservationIgnored private var fireLeft: Double = 0
    @ObservationIgnored private var spawnQueue: [(Double, Kind, Double)] = []
    @ObservationIgnored private var waveTime: Double = 0
    @ObservationIgnored private var bannerLeft: Double = 0
    @ObservationIgnored private var dragStart: (x: Double, y: Double)?
    @ObservationIgnored private var bombArmed = true
    @ObservationIgnored private var bombCooldown: Double = 0
    @ObservationIgnored private var bossesBeaten = 0

    init() {
        best = UserDefaults.standard.integer(forKey: "comete.best")
    }

    var half: Double { Double(rows) / 2 }

    func configure(rows: Int, topReserve: Double, bottomReserve: Double) {
        self.rows = max(140, rows)
        topLimit = max(12, topReserve)
        bottomLimit = Double(self.rows) - max(10, bottomReserve)
        if phase != .playing {
            shipX = Double(cols) / 2
            shipY = bottomLimit - 14
        }
    }

    // MARK: Partie

    func start() {
        score = 0
        lives = 3
        bombs = 2
        power = 1
        shield = 0
        wave = 0
        bossesBeaten = 0
        enemies.removeAll()
        shots.removeAll()
        enemyShots.removeAll()
        bonuses.removeAll()
        sparks.removeAll()
        bossHP = nil
        shipX = Double(cols) / 2
        shipY = bottomLimit - 14
        invincible = 1.5
        phase = .playing
        nextWave()
        SoundPlayer.shared.play(.go, volume: 0.5)
    }

    private func say(_ s: String) {
        banner = s
        bannerLeft = 1.6
    }

    private func nextWave() {
        wave += 1
        waveTime = 0
        spawnQueue.removeAll()
        if wave % 5 == 0 {
            say(L("ALERTE : VAISSEAU MÈRE !"))
            spawnQueue.append((1.5, .boss, 0.5))
            SoundPlayer.shared.play(.roar, volume: 0.5)
            return
        }
        say(L("VAGUE \(wave)"))
        let n = 6 + wave * 2
        var t = 1.2
        for k in 0..<n {
            var kind: Kind = .drone
            let r = Int.random(in: 0..<100)
            if wave >= 2 && r < 25 { kind = .zigzag }
            if wave >= 3 && r >= 25 && r < 40 { kind = .shooter }
            if wave >= 4 && r >= 90 { kind = .tank }
            // Les drones arrivent en file, les autres un par un
            let x = kind == .drone ? 0.15 + 0.7 * Double((k / 3) % 4) / 3 : Double.random(in: 0.12...0.88)
            spawnQueue.append((t, kind, x))
            t += kind == .drone ? 0.35 : 0.8
            if k % 3 == 2 { t += 0.6 }
        }
    }

    private func spawn(_ kind: Kind, at fx: Double) {
        let x = fx * Double(cols)
        let speedUp = 1 + Double(wave) * 0.05
        switch kind {
        case .drone:
            enemies.append(Enemy(kind: .drone, x: x, y: -6, vx: 0, vy: 32 * speedUp, hp: 1, maxHP: 1))
        case .zigzag:
            enemies.append(Enemy(kind: .zigzag, x: x, y: -6, vx: Bool.random() ? 45 : -45, vy: 38 * speedUp, hp: 1, maxHP: 1))
        case .shooter:
            enemies.append(Enemy(kind: .shooter, x: x, y: -6, vx: 0, vy: 40, hp: 2, maxHP: 2, fire: 1.0))
        case .tank:
            enemies.append(Enemy(kind: .tank, x: x, y: -8, vx: 0, vy: 14 * speedUp, hp: 6, maxHP: 6, fire: 2.0))
        case .boss:
            let hp = 70 + 30 * bossesBeaten
            enemies.append(Enemy(kind: .boss, x: Double(cols) / 2, y: -14, vx: 26, vy: 20, hp: hp, maxHP: hp, fire: 1.2))
        }
    }

    // MARK: Commandes

    func dragBegan() { dragStart = (x: shipX, y: shipY) }

    func drag(dx: Double, dy: Double) {
        guard phase == .playing else { return }
        if dragStart == nil { dragBegan() }
        guard let s = dragStart else { return }
        shipX = min(Double(cols) - 6, max(6, s.x + dx * 1.25))
        shipY = min(bottomLimit - 6, max(topLimit + 8, s.y + dy * 1.25))
    }

    func dragEnded() { dragStart = nil }

    func bomb() {
        guard phase == .playing, bombs > 0, bombCooldown <= 0 else { return }
        bombs -= 1
        bombCooldown = 1
        bombFlash = 0.6
        shake = 0.5
        enemyShots.removeAll()
        for i in enemies.indices {
            enemies[i].hp -= enemies[i].kind == .boss ? 12 : 99
            enemies[i].flash = 0.2
        }
        SoundPlayer.shared.play(.boom, volume: 0.9)
        Haptics.success()
    }

    func hinge(_ degrees: Double?) {
        guard let degrees, degrees >= HingeMapping.openThreshold else { return }
        // Plier à moitié (sous 145°) : boum. On réarme en rouvrant au-dessus de 160°.
        if degrees > 160 { bombArmed = true }
        if degrees < 145 && bombArmed && phase == .playing {
            bombArmed = false
            bomb()
        }
    }

    // MARK: Le temps

    func tick(dt: Double) {
        frame &+= 1
        time += dt
        if bannerLeft > 0 {
            bannerLeft -= dt
            if bannerLeft <= 0 { banner = nil }
        }
        if shake > 0 { shake -= dt }
        if bombFlash > 0 { bombFlash -= dt }
        if bombCooldown > 0 { bombCooldown -= dt }
        moveSparks(dt)
        guard phase == .playing else { return }
        if invincible > 0 { invincible -= dt }
        if shield > 0 { shield -= dt }

        // Les vagues
        waveTime += dt
        while let first = spawnQueue.first, first.0 <= waveTime {
            spawnQueue.removeFirst()
            spawn(first.1, at: first.2)
        }
        if spawnQueue.isEmpty && enemies.isEmpty && waveTime > 1 { nextWave() }

        // Le tir automatique
        fireLeft -= dt
        if fireLeft <= 0 {
            fireLeft = 0.17
            shots.append(Shot(x: shipX, y: shipY - 6, vx: 0, vy: -190))
            if power >= 2 {
                shots.append(Shot(x: shipX - 4, y: shipY - 3, vx: 0, vy: -190))
                shots.append(Shot(x: shipX + 4, y: shipY - 3, vx: 0, vy: -190))
            }
            if power >= 3 {
                shots.append(Shot(x: shipX - 3, y: shipY - 4, vx: -45, vy: -180))
                shots.append(Shot(x: shipX + 3, y: shipY - 4, vx: 45, vy: -180))
            }
            if frame % 2 == 0 { SoundPlayer.shared.play(.tock, volume: 0.08) }
        }
        for i in shots.indices { shots[i].x += shots[i].vx * dt; shots[i].y += shots[i].vy * dt }
        shots.removeAll { $0.y < -4 || $0.x < -4 || $0.x > Double(cols + 4) }
        for i in enemyShots.indices { enemyShots[i].x += enemyShots[i].vx * dt; enemyShots[i].y += enemyShots[i].vy * dt }
        enemyShots.removeAll { $0.y > Double(rows + 4) || $0.y < -10 || $0.x < -4 || $0.x > Double(cols + 4) }

        moveEnemies(dt)
        collide()

        // Les bonus qui descendent
        for i in bonuses.indices { bonuses[i].y += 28 * dt }
        bonuses.removeAll { $0.y > Double(rows + 6) }
        var k = 0
        while k < bonuses.count {
            let b = bonuses[k]
            if abs(b.x - shipX) < 8 && abs(b.y - shipY) < 8 {
                switch b.kind {
                case .power: power = min(3, power + 1); say(L("PUISSANCE +1"))
                case .shield: shield = 7; say(L("BOUCLIER"))
                case .bomb: bombs = min(5, bombs + 1); say(L("BOMBE +1"))
                }
                SoundPlayer.shared.play(.chime, volume: 0.6)
                Haptics.tap()
                bonuses.remove(at: k)
                continue
            }
            k += 1
        }
        bossHP = enemies.first(where: { $0.kind == .boss }).map { Double(max(0, $0.hp)) / Double($0.maxHP) }
    }

    private func moveEnemies(_ dt: Double) {
        for i in enemies.indices {
            enemies[i].t += dt
            if enemies[i].flash > 0 { enemies[i].flash -= dt }
            let e = enemies[i]
            switch e.kind {
            case .drone:
                enemies[i].x += sin(e.t * 3) * 22 * dt
                enemies[i].y += e.vy * dt
            case .zigzag:
                enemies[i].x += e.vx * dt
                if enemies[i].x < 6 || enemies[i].x > Double(cols) - 6 { enemies[i].vx = -e.vx }
                enemies[i].y += e.vy * dt
            case .shooter:
                // descend, s'arrête pour tirer, puis repart
                let stop = Double(rows) * 0.25
                if e.t < 6 { enemies[i].y += (e.y < stop ? e.vy : 4) * dt } else { enemies[i].y += 60 * dt }
                enemies[i].fire -= dt
                if enemies[i].fire <= 0 && e.y > 0 && e.t < 6 {
                    enemies[i].fire = max(0.8, 1.7 - Double(wave) * 0.05)
                    aimShot(from: e.x, e.y + 4, speed: 70)
                }
            case .tank:
                enemies[i].y += e.vy * dt
                enemies[i].fire -= dt
                if enemies[i].fire <= 0 && e.y > 0 {
                    enemies[i].fire = 2.2
                    for a in [-0.5, 0.0, 0.5] { enemyShots.append(Shot(x: e.x, y: e.y + 5, vx: sin(a) * 60, vy: cos(a) * 60)) }
                }
            case .boss:
                let home = Double(rows) * 0.16
                if e.y < home { enemies[i].y += e.vy * dt }
                enemies[i].x += e.vx * dt
                if enemies[i].x < 20 || enemies[i].x > Double(cols) - 20 { enemies[i].vx = -e.vx }
                enemies[i].fire -= dt
                if enemies[i].fire <= 0 && e.y >= home - 1 {
                    let angry = Double(e.hp) / Double(e.maxHP) < 0.5
                    enemies[i].fire = angry ? 0.8 : 1.2
                    let count = angry ? 7 : 5
                    for n in 0..<count {
                        let a = (Double(n) - Double(count - 1) / 2) * 0.28 + sin(e.t) * 0.15
                        enemyShots.append(Shot(x: e.x, y: e.y + 8, vx: sin(a) * 65, vy: cos(a) * 65))
                    }
                    if angry { aimShot(from: e.x - 12, e.y + 6, speed: 85); aimShot(from: e.x + 12, e.y + 6, speed: 85) }
                }
            }
        }
        // Ceux qui sortent par le bas disparaissent
        enemies.removeAll { $0.y > Double(rows + 12) }
    }

    private func aimShot(from x: Double, _ y: Double, speed: Double) {
        let dx = shipX - x, dy = shipY - y
        let d = max(1, hypot(dx, dy))
        enemyShots.append(Shot(x: x, y: y, vx: dx / d * speed, vy: dy / d * speed))
    }

    static func hitbox(_ k: Kind) -> (w: Double, h: Double) {
        switch k {
        case .drone: return (7, 6)
        case .zigzag: return (7, 7)
        case .shooter: return (9, 7)
        case .tank: return (11, 8)
        case .boss: return (31, 14)
        }
    }

    private func collide() {
        // Nos tirs sur les ennemis
        var si = 0
        while si < shots.count {
            let s = shots[si]
            var hit = false
            for i in enemies.indices {
                let hb = Self.hitbox(enemies[i].kind)
                if abs(s.x - enemies[i].x) < hb.w / 2 + 1 && abs(s.y - enemies[i].y) < hb.h / 2 + 2 {
                    enemies[i].hp -= 1
                    enemies[i].flash = 0.08
                    hit = true
                    break
                }
            }
            if hit { shots.remove(at: si) } else { si += 1 }
        }
        // Les ennemis détruits
        var i = 0
        while i < enemies.count {
            let e = enemies[i]
            if e.hp <= 0 {
                explode(e)
                enemies.remove(at: i)
                continue
            }
            // Choc avec le vaisseau
            let hb = Self.hitbox(e.kind)
            if abs(e.x - shipX) < hb.w / 2 + 3 && abs(e.y - shipY) < hb.h / 2 + 3 {
                if e.kind != .boss { enemies[i].hp = 0 }
                hurt()
            }
            i += 1
        }
        // Les tirs ennemis sur le vaisseau
        var k = 0
        while k < enemyShots.count {
            let s = enemyShots[k]
            if abs(s.x - shipX) < 3 && abs(s.y - shipY) < 4 {
                enemyShots.remove(at: k)
                hurt()
                continue
            }
            k += 1
        }
    }

    private func hurt() {
        guard invincible <= 0, phase == .playing else { return }
        if shield > 0 {
            shield = 0
            invincible = 0.8
            SoundPlayer.shared.play(.clunk, volume: 0.6)
            return
        }
        lives -= 1
        invincible = 2
        shake = 0.4
        power = max(1, power - 1)
        burst(shipX, shipY, color: 0xFF8A3D, count: 18)
        SoundPlayer.shared.play(.bang, volume: 0.7)
        Haptics.error()
        if lives <= 0 {
            phase = .over
            if score > best {
                best = score
                UserDefaults.standard.set(best, forKey: "comete.best")
            }
        }
    }

    private func explode(_ e: Enemy) {
        let points: Int
        switch e.kind {
        case .drone: points = 10
        case .zigzag: points = 15
        case .shooter: points = 30
        case .tank: points = 60
        case .boss: points = 1000 + 500 * bossesBeaten
        }
        score += points
        let big = e.kind == .boss || e.kind == .tank
        burst(e.x, e.y, color: e.kind == .boss ? 0xFF7BEA : 0xFFC93C, count: big ? 40 : 12)
        if e.kind == .boss {
            bossesBeaten += 1
            shake = 0.8
            bombs = min(5, bombs + 1)
            say(L("VAISSEAU MÈRE DÉTRUIT !"))
            for _ in 0..<3 { bonuses.append(Bonus(kind: .power, x: e.x + Double.random(in: -12...12), y: e.y)) }
            SoundPlayer.shared.play(.applause, volume: 0.6)
        } else {
            SoundPlayer.shared.play(big ? .boom : .pop, volume: big ? 0.6 : 0.35)
            if Double.random(in: 0...1) < (e.kind == .tank ? 0.6 : 0.07) {
                let r = Int.random(in: 0..<10)
                bonuses.append(Bonus(kind: r < 5 ? .power : (r < 8 ? .shield : .bomb), x: e.x, y: e.y))
            }
        }
        if big { shake = max(shake, 0.3) }
    }

    private func burst(_ x: Double, _ y: Double, color: UInt32, count: Int) {
        for _ in 0..<count {
            let a = Double.random(in: 0...(2 * .pi)), s = Double.random(in: 20...90)
            sparks.append(Spark(x: x, y: y, vx: cos(a) * s, vy: sin(a) * s, life: Double.random(in: 0.3...0.8),
                                color: [color, 0xFFFFFF, 0xFF4F4F, 0xFFE066].randomElement() ?? color))
        }
    }

    private func moveSparks(_ dt: Double) {
        for i in sparks.indices {
            sparks[i].x += sparks[i].vx * dt
            sparks[i].y += sparks[i].vy * dt
            sparks[i].vx *= pow(0.2, dt)
            sparks[i].vy *= pow(0.2, dt)
            sparks[i].life -= dt
        }
        sparks.removeAll { $0.life <= 0 }
    }

    // MARK: Démo

    func demo() {
        start()
        power = 3
        wave = 2
        nextWave()
    }

    func demoMove() {
        guard phase == .playing else { return }
        let target = enemies.min(by: { abs($0.x - shipX) < abs($1.x - shipX) })?.x ?? Double(cols) / 2
        shipX += max(-6, min(6, target - shipX))
    }
}
