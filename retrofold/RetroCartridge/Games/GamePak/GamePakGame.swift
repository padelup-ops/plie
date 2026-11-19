// GamePakGame.swift
// RetroCartridge
//
// The Game Pak cartridge: plays the player's own Game Boy and Game Boy Color
// games with the SameBoy core (GBCore). RetroFold ships no games; the title
// screen lists the games the player imported and offers to load another.
//
// Controls: the D-Pad, A, B and START go to the game. SELECT goes to the game
// too; pressing it twice quickly opens RetroFold's pause menu (with Eject).
// Folding pauses, as with every cartridge.

import AVFoundation
import GBCore
import SwiftUI
import UIKit

final class GamePakGame: PixelGameProtocol {
    var gameType: GameType = .gamePak
    var gameState: GameState = .menu
    var score: Int = 0
    var level: Int = 1
    var highScore: Int = 0
    var mode: GameMode = .standard
    var palette: GamePalette = .gamePak
    var pendingSounds: [GameSound] = []

    // MARK: - Library screen

    private(set) var games: [RomEntry] = []
    /// 0 is "Load a game", then the games.
    private(set) var selection = 0
    /// A message under the list (an import that failed).
    var notice: String?

    // MARK: - Console

    private var core: OpaquePointer?
    private var current: RomEntry?
    private var accumulator: TimeInterval = 0
    private static let frameTime: TimeInterval = 70224.0 / 4194304.0
    private var image: CGImage?
    private var releaseAt: [Int32: Int] = [:]
    private var frameCount = 0
    private var lastSave = Date()
    private var lastSelectTap: Date?
    private var pendingSelect: Date?

    private let audio = GamePakAudio()

    private var observers: [NSObjectProtocol] = []

    init() {
        reloadLibrary()
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: RomLibrary.imported, object: nil, queue: .main) { [weak self] n in
            guard let self else { return }
            self.reloadLibrary()
            // One game added: it starts. Several: the list shows them.
            if let id = n.object as? String, let e = self.games.first(where: { $0.id == id }), self.gameState == .menu {
                self.start(e)
            } else if !self.games.isEmpty {
                self.selection = 1
            }
        })
        // Leaving the app saves the game, in case iOS closes it later.
        observers.append(nc.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.persist()
        })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        persist()
        audio.stop()
        if let core { gbk_destroy(core) }
    }

    func reloadLibrary() {
        games = RomLibrary.entries()
        selection = min(selection, games.count)
        if selection == 0, !games.isEmpty, current == nil { selection = 1 }
    }

    // MARK: - Lifecycle

    func reset() {
        // A new round of the cartridge is its library screen.
        persist()
        stopCore()
        gameState = .menu
        reloadLibrary()
    }

    func pause() {
        guard gameState == .playing else { return }
        gameState = .paused
        persist()
        audio.pause()
        releaseAllKeys()
    }

    func resume() {
        guard gameState == .paused else { return }
        gameState = .playing
        accumulator = 0
        audio.resume()
    }

    private func start(_ entry: RomEntry) {
        guard let data = try? Data(contentsOf: RomLibrary.romURL(entry)) else {
            notice = String(localized: "This game can't be opened.")
            return
        }
        stopCore()
        guard let k = gbk_create(1, UInt32(audio.sampleRate)) else { return }
        core = k
        data.withUnsafeBytes { gbk_load_rom(k, $0.bindMemory(to: UInt8.self).baseAddress, data.count) }
        if let save = try? Data(contentsOf: RomLibrary.batteryURL(entry)) {
            save.withUnsafeBytes { gbk_battery_load(k, $0.bindMemory(to: UInt8.self).baseAddress, save.count) }
        }
        // Pick up exactly where the player left off.
        if let state = try? Data(contentsOf: RomLibrary.stateURL(entry)) {
            _ = state.withUnsafeBytes { gbk_state_load(k, $0.bindMemory(to: UInt8.self).baseAddress, state.count) }
        }
        current = entry
        RomLibrary.markPlayed(entry)
        notice = nil
        accumulator = 0
        gameState = .playing
        audio.start(core: k)
    }

    private func stopCore() {
        audio.stop()
        if let core { gbk_destroy(core) }
        core = nil
        current = nil
        image = nil
    }

    /// Writes the cartridge's battery save and a snapshot of the console.
    func persist() {
        guard let core, let current else { return }
        let n = gbk_battery_size(core)
        if n > 0 {
            var buf = Data(count: n)
            let written = buf.withUnsafeMutableBytes { gbk_battery_save(core, $0.bindMemory(to: UInt8.self).baseAddress, n) }
            if written > 0 { try? buf.prefix(written).write(to: RomLibrary.batteryURL(current), options: .atomic) }
        }
        let s = gbk_state_size(core)
        if s > 0 {
            var buf = Data(count: s)
            buf.withUnsafeMutableBytes { gbk_state_save(core, $0.bindMemory(to: UInt8.self).baseAddress) }
            try? buf.write(to: RomLibrary.stateURL(current), options: .atomic)
        }
        lastSave = Date()
    }

    // MARK: - Frame

    func update(deltaTime: TimeInterval) {
        guard gameState == .playing, let core else { return }
        if let at = pendingSelect, Date() >= at {
            pendingSelect = nil
            tap(Int32(GBK_SELECT))
        }
        accumulator += deltaTime
        var frames = 0
        while accumulator >= Self.frameTime, frames < 3 {
            accumulator -= Self.frameTime
            frames += 1
            frameCount += 1
            for (key, at) in releaseAt where at <= frameCount {
                gbk_set_key(core, key, 0)
                releaseAt[key] = nil
            }
            gbk_run_frame(core)
        }
        if accumulator > Self.frameTime * 3 { accumulator = 0 }
        if frames > 0 { image = makeImage(core) }
        if Date().timeIntervalSince(lastSave) > 20 { persist() }
    }

    private func makeImage(_ core: OpaquePointer) -> CGImage? {
        guard let px = gbk_pixels(core) else { return nil }
        let data = Data(bytes: px, count: 160 * 144 * 4)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: 160, height: 144, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 160 * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    func render(context: inout GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
        if gameState != .menu, let image {
            // Whole pixels when possible, centered, no smoothing.
            let scale = min(size.width / 160, size.height / 144)
            let w = 160 * scale, h = 144 * scale
            let rect = CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
            context.withCGContext { cg in
                cg.interpolationQuality = .none
                cg.saveGState()
                cg.translateBy(x: 0, y: rect.minY * 2 + rect.height)
                cg.scaleBy(x: 1, y: -1)
                cg.draw(image, in: rect)
                cg.restoreGState()
            }
            return
        }
        drawLibrary(context: &context, size: size)
    }

    private func drawLibrary(context: inout GraphicsContext, size: CGSize) {
        let u = min(size.width, size.height) / 20
        let green = Color(hex: "#9CFFB8")
        var y = u * 1.4
        context.draw(Text("GAME PAK").font(.pixel(u * 1.3, bold: true)).foregroundColor(green),
                     at: CGPoint(x: size.width / 2, y: y))
        y += u * 1.6
        context.draw(Text("YOUR OWN GAME BOY GAMES").font(.pixel(u * 0.62)).foregroundColor(green.opacity(0.6)),
                     at: CGPoint(x: size.width / 2, y: y))
        y += u * 1.8
        let rows = [String(localized: "+ LOAD A GAME (.GB / .GBC)")] + games.map { $0.title.uppercased() }
        let visible = max(1, Int((size.height - y - u * 3.2) / (u * 1.5)))
        let first = max(0, min(selection - visible / 2, rows.count - visible))
        for (i, row) in rows.enumerated().dropFirst(first).prefix(visible) {
            let selected = i == selection
            let label = (selected ? "▶ " : "  ") + row
            context.draw(Text(label).font(.pixel(u * 0.8, bold: selected)).foregroundColor(selected ? green : green.opacity(0.55)),
                         at: CGPoint(x: u * 1.2, y: y), anchor: .leading)
            y += u * 1.5
        }
        let foot = notice ?? (games.isEmpty
            ? String(localized: "PRESS A, THEN PICK A GAME FILE IN FILES")
            : String(localized: "A: PLAY   SELECT: EJECT"))
        context.draw(Text(foot.uppercased()).font(.pixel(u * 0.55)).foregroundColor(notice == nil ? green.opacity(0.5) : Color(hex: "#FFB703")),
                     at: CGPoint(x: size.width / 2, y: size.height - u * 1.2))
    }

    // MARK: - Input

    func handleInput(action: GameInputAction) {
        switch gameState {
        case .menu:
            menuInput(action)
        case .paused:
            if action == .buttonStartPressed { resume() }
        case .playing:
            playInput(action)
        case .gameOver:
            break
        }
    }

    private func menuInput(_ action: GameInputAction) {
        let count = games.count + 1
        switch action {
        case .dpadUpPressed: selection = (selection - 1 + count) % count
        case .dpadDownPressed: selection = (selection + 1) % count
        case .buttonAPressed, .buttonStartPressed:
            if selection == 0 {
                NotificationCenter.default.post(name: RomLibrary.importRequested, object: nil)
            } else {
                start(games[selection - 1])
            }
        default: break
        }
    }

    private func playInput(_ action: GameInputAction) {
        guard let core else { return }
        func set(_ key: Int32, _ down: Bool) {
            releaseAt[key] = nil
            gbk_set_key(core, key, down ? 1 : 0)
        }
        switch action {
        case .dpadUpPressed: set(Int32(GBK_UP), true)
        case .dpadUpReleased: set(Int32(GBK_UP), false)
        case .dpadDownPressed: set(Int32(GBK_DOWN), true)
        case .dpadDownReleased: set(Int32(GBK_DOWN), false)
        case .dpadLeftPressed: set(Int32(GBK_LEFT), true)
        case .dpadLeftReleased: set(Int32(GBK_LEFT), false)
        case .dpadRightPressed: set(Int32(GBK_RIGHT), true)
        case .dpadRightReleased: set(Int32(GBK_RIGHT), false)
        case .buttonAPressed: set(Int32(GBK_A), true)
        case .buttonAReleased: set(Int32(GBK_A), false)
        case .buttonBPressed: set(Int32(GBK_B), true)
        case .buttonBReleased: set(Int32(GBK_B), false)
        case .buttonStartPressed: tap(Int32(GBK_START))
        case .buttonSelectPressed: selectTapped()
        default: break
        }
    }

    /// START and SELECT are pills without a release: a short press of a few frames.
    private func tap(_ key: Int32) {
        guard let core else { return }
        gbk_set_key(core, key, 1)
        releaseAt[key] = frameCount + 6
    }

    /// SELECT once: the game's Select. Twice quickly: RetroFold's pause menu.
    func selectTapped() {
        let now = Date()
        if let last = lastSelectTap, now.timeIntervalSince(last) < 0.4 {
            lastSelectTap = nil
            pendingSelect = nil
            pause()
            return
        }
        lastSelectTap = now
        pendingSelect = now.addingTimeInterval(0.4)
    }

    private func releaseAllKeys() {
        guard let core else { return }
        for k in 0..<8 { gbk_set_key(core, Int32(k), 0) }
        releaseAt.removeAll()
    }
}

// MARK: - Sound

/// The console's sound, pulled from the core's buffer by the audio thread.
final class GamePakAudio {
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    let sampleRate: Double = 48_000
    private let corePtr = UnsafeMutablePointer<OpaquePointer?>.allocate(capacity: 1)
    private let scratch = UnsafeMutablePointer<Int16>.allocate(capacity: 8192)

    init() { corePtr.initialize(to: nil) }

    deinit {
        stop()
        corePtr.deallocate()
        scratch.deallocate()
    }

    func start(core: OpaquePointer) {
        stop()
        corePtr.pointee = core
        guard UserDefaults.standard.object(forKey: "soundOn") == nil || UserDefaults.standard.bool(forKey: "soundOn") else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let ptr = corePtr, buf = scratch
        let n = AVAudioSourceNode(format: format) { _, _, frameCount, abl -> OSStatus in
            let list = UnsafeMutableAudioBufferListPointer(abl)
            let frames = Int(frameCount)
            var got = 0
            if let core = ptr.pointee {
                got = Int(gbk_read_audio(core, buf, min(frames, 4096)))
            }
            for (c, b) in list.enumerated() {
                guard let out = b.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for i in 0..<frames {
                    out[i] = i < got ? Float(buf[i * 2 + min(c, 1)]) / 32768 : 0
                }
            }
            return noErr
        }
        node = n
        engine.attach(n)
        engine.connect(n, to: engine.mainMixerNode, format: format)
        try? engine.start()
    }

    func pause() { engine.pause() }
    func resume() { if node != nil { try? engine.start() } }

    func stop() {
        engine.stop()
        if let node {
            engine.detach(node)
        }
        node = nil
        corePtr.pointee = nil
    }
}
