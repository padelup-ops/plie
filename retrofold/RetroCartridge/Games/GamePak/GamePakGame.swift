// GamePakGame.swift
// RetroCartridge
//
// The Game Pak cartridge: plays the player's own Game Boy, Game Boy Color,
// Game Boy Advance and Nintendo DS games (see GamePakMachines.swift).
// RetroFold ships no games; the title screen lists the games the player
// imported and offers to load more.
//
// Controls: the D-Pad, A, B and START go to the game. SELECT goes to the game
// too; pressing it twice quickly opens RetroFold's pause menu (with Eject).
// A game controller adds X, Y, L and R, and shows the game full screen.
// Folding pauses, as with every cartridge.

import AVFoundation
import GameController
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

    private var machine: GamePakMachine?
    private(set) var current: RomEntry?
    private var accumulator: TimeInterval = 0
    private(set) var image: CGImage?
    /// Buttons held on the console (on screen) and on a game controller; the game gets both.
    private var consoleHeld = Set<PakButton>()
    private var padHeld = Set<PakButton>()
    private var sent = Set<PakButton>()
    private var releaseAt: [PakButton: Int] = [:]
    private var frameCount = 0
    private var lastSave = Date()
    private var lastSelectTap: Date?
    private var pendingSelect: Date?
    private var padMenuHeld = Set<PakButton>()

    private let audio = GamePakAudio()
    private var observers: [NSObjectProtocol] = []

    /// A game controller is connected: the game shows full screen.
    static var hasController: Bool { !GCController.controllers().isEmpty }

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
        GCController.startWirelessControllerDiscovery {}
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        persist()
        audio.stop()
        machine?.close()
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
        stopMachine()
        gameState = .menu
        reloadLibrary()
    }

    func pause() {
        guard gameState == .playing else { return }
        gameState = .paused
        persist()
        audio.pause()
        releaseAll()
    }

    func resume() {
        guard gameState == .paused else { return }
        gameState = .playing
        accumulator = 0
        audio.resume()
    }

    private func start(_ entry: RomEntry) {
        stopMachine()
        let rom = RomLibrary.romURL(entry)
        let m: GamePakMachine?
        switch entry.system {
        case .gb: m = SameBoyMachine(rom: rom)
        case .gba, .nds: m = RetroCoreMachine(system: entry.system, rom: rom, saveDir: RomLibrary.saveFolder(entry))
        }
        guard let m else {
            notice = String(localized: "THIS GAME CAN'T BE OPENED") + (RetroCoreMachine.lastError.map { " (\($0))" } ?? "")
            return
        }
        machine = m
        if let save = try? Data(contentsOf: RomLibrary.batteryURL(entry)) { m.loadBattery(save) }
        // Pick up exactly where the player left off.
        if let state = try? Data(contentsOf: RomLibrary.stateURL(entry)) { m.loadState(state) }
        current = entry
        RomLibrary.markPlayed(entry)
        notice = nil
        accumulator = 0
        gameState = .playing
        audio.start(machine: m)
    }

    private func stopMachine() {
        audio.stop()
        machine?.close()
        machine = nil
        current = nil
        image = nil
        consoleHeld.removeAll()
        sent.removeAll()
    }

    /// Writes the cartridge's save and a snapshot of the console.
    func persist() {
        guard let machine, let current else { return }
        if let b = machine.battery() { try? b.write(to: RomLibrary.batteryURL(current), options: .atomic) }
        if let s = machine.state() { try? s.write(to: RomLibrary.stateURL(current), options: .atomic) }
        lastSave = Date()
    }

    // MARK: - Frame

    func update(deltaTime: TimeInterval) {
        pollController()
        guard gameState == .playing, let machine else { return }
        if let at = pendingSelect, Date() >= at {
            pendingSelect = nil
            tap(.select)
        }
        accumulator += deltaTime
        var frames = 0
        while accumulator >= machine.frameTime, frames < 3 {
            accumulator -= machine.frameTime
            frames += 1
            frameCount += 1
            for (key, at) in releaseAt where at <= frameCount {
                consoleHeld.remove(key)
                releaseAt[key] = nil
            }
            sync()
            machine.runFrame()
        }
        if accumulator > machine.frameTime * 3 { accumulator = 0 }
        if frames > 0 { image = machine.makeImage() }
        if Date().timeIntervalSince(lastSave) > 20 { persist() }
    }

    /// Sends the game the buttons held on the console and on the controller.
    private func sync() {
        guard let machine else { return }
        let held = consoleHeld.union(padHeld)
        for b in held.subtracting(sent) { machine.set(b, true) }
        for b in sent.subtracting(held) { machine.set(b, false) }
        sent = held
    }

    // MARK: - Drawing

    /// Where the picture goes in a canvas of the given size (centered, as large as fits).
    func pictureRect(in size: CGSize) -> CGRect {
        let px = machine?.pixelSize ?? CGSize(width: 160, height: 144)
        let scale = min(size.width / px.width, size.height / px.height)
        let w = px.width * scale, h = px.height * scale
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    func render(context: inout GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
        if gameState != .menu, let image {
            let rect = pictureRect(in: size)
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
        context.draw(Text("YOUR OWN GB · GBC · GBA · DS GAMES").font(.pixel(u * 0.58)).foregroundColor(green.opacity(0.6)),
                     at: CGPoint(x: size.width / 2, y: y))
        y += u * 1.8
        let rows = [String(localized: "+ LOAD GAMES")] + games.map { "\($0.system.badge)  \($0.title.uppercased())" }
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
            ? String(localized: "PRESS A, THEN PICK YOUR GAME FILES IN FILES")
            : String(localized: "A: PLAY   SELECT: EJECT"))
        context.draw(Text(foot.uppercased()).font(.pixel(u * 0.55)).foregroundColor(notice == nil ? green.opacity(0.5) : Color(hex: "#FFB703")),
                     at: CGPoint(x: size.width / 2, y: size.height - u * 1.2))
    }

    // MARK: - Touch (DS)

    /// A touch on the picture (canvas coordinates), for the DS touch screen.
    func touch(at point: CGPoint?, in size: CGSize) {
        guard gameState == .playing, let machine, machine.hasTouch else { return }
        guard let point else {
            machine.touch(x: 0, y: 0, pressed: false)
            return
        }
        let rect = pictureRect(in: size)
        let px = machine.pixelSize
        let x = Int(((point.x - rect.minX) / rect.width * px.width).rounded(.down))
        let y = Int(((point.y - rect.minY) / rect.height * px.height).rounded(.down))
        machine.touch(x: min(max(x, 0), Int(px.width) - 1), y: min(max(y, 0), Int(px.height) - 1), pressed: true)
    }

    var acceptsTouch: Bool { gameState == .playing && (machine?.hasTouch ?? false) }

    // MARK: - DS on the open Duo

    /// A DS game is running: the open Duo shows its two screens big, like a real DS.
    var isDS: Bool { current?.system == .nds }

    /// The DS picture split into its top screen and its touch screen.
    func dsScreens() -> (top: CGImage, bottom: CGImage)? {
        guard let image, image.height >= 2 else { return nil }
        let h = image.height / 2
        guard let top = image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: h)),
              let bottom = image.cropping(to: CGRect(x: 0, y: h, width: image.width, height: h)) else { return nil }
        return (top, bottom)
    }

    /// A touch on the DS touch screen, from 0 to 1 across and down (nil: released).
    func touchDS(_ p: CGPoint?) {
        guard gameState == .playing, let machine, machine.hasTouch else { return }
        let px = machine.pixelSize
        guard let p else {
            machine.touch(x: 0, y: 0, pressed: false)
            return
        }
        let x = Int(min(max(p.x, 0), 0.999) * px.width)
        let y = Int(px.height / 2 + min(max(p.y, 0), 0.999) * px.height / 2)
        machine.touch(x: x, y: y, pressed: true)
    }

    /// The on-screen buttons of the big DS layout (every button, L / R / X / Y included).
    func overlayButton(_ b: PakButton, _ down: Bool) {
        guard gameState == .playing else { return }
        releaseAt[b] = nil
        if down { consoleHeld.insert(b) } else { consoleHeld.remove(b) }
    }

    // MARK: - Console input

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
        case .buttonAPressed:
            if selection == 0 {
                NotificationCenter.default.post(name: RomLibrary.importRequested, object: nil)
            } else {
                start(games[selection - 1])
            }
        case .buttonStartPressed:
            if selection > 0 { start(games[selection - 1]) }
        default: break
        }
    }

    private func playInput(_ action: GameInputAction) {
        func hold(_ b: PakButton, _ down: Bool) {
            releaseAt[b] = nil
            if down { consoleHeld.insert(b) } else { consoleHeld.remove(b) }
        }
        switch action {
        case .dpadUpPressed: hold(.up, true)
        case .dpadUpReleased: hold(.up, false)
        case .dpadDownPressed: hold(.down, true)
        case .dpadDownReleased: hold(.down, false)
        case .dpadLeftPressed: hold(.left, true)
        case .dpadLeftReleased: hold(.left, false)
        case .dpadRightPressed: hold(.right, true)
        case .dpadRightReleased: hold(.right, false)
        case .buttonAPressed: hold(.a, true)
        case .buttonAReleased: hold(.a, false)
        case .buttonBPressed: hold(.b, true)
        case .buttonBReleased: hold(.b, false)
        case .buttonStartPressed: tap(.start)
        case .buttonSelectPressed: selectTapped()
        default: break
        }
    }

    /// START and SELECT are pills without a release: a short press of a few frames.
    private func tap(_ b: PakButton) {
        consoleHeld.insert(b)
        releaseAt[b] = frameCount + 6
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

    private func releaseAll() {
        consoleHeld.removeAll()
        padHeld.removeAll()
        releaseAt.removeAll()
        sync()
    }

    // MARK: - Game controller

    /// Reads the connected controller every frame: in a game, every button goes to it (Xbox / PlayStation
    /// layouts: the bottom face button is B and the right one A, as on Nintendo hardware positions);
    /// in the library, the D-Pad and A / B pick a game. Double-tapping the Options / Select button pauses.
    private func pollController() {
        guard let pad = GCController.current?.extendedGamepad ?? GCController.controllers().first?.extendedGamepad else {
            if !padHeld.isEmpty { padHeld.removeAll() }
            return
        }
        var held = Set<PakButton>()
        let dx = pad.dpad.xAxis.value + pad.leftThumbstick.xAxis.value
        let dy = pad.dpad.yAxis.value + pad.leftThumbstick.yAxis.value
        if dy > 0.5 { held.insert(.up) }
        if dy < -0.5 { held.insert(.down) }
        if dx < -0.5 { held.insert(.left) }
        if dx > 0.5 { held.insert(.right) }
        if pad.buttonB.isPressed { held.insert(.a) }
        if pad.buttonA.isPressed { held.insert(.b) }
        if pad.buttonY.isPressed { held.insert(.x) }
        if pad.buttonX.isPressed { held.insert(.y) }
        if pad.leftShoulder.isPressed || pad.leftTrigger.isPressed { held.insert(.l) }
        if pad.rightShoulder.isPressed || pad.rightTrigger.isPressed { held.insert(.r) }
        if pad.buttonMenu.isPressed { held.insert(.start) }
        let options = pad.buttonOptions?.isPressed ?? false

        switch gameState {
        case .playing:
            if options && !padMenuHeld.contains(.select) { selectTapped() }
            padHeld = held
        case .paused:
            if held.contains(.start) && !padMenuHeld.contains(.start) { resume() }
            padHeld.removeAll()
        case .menu:
            let pressed = held.subtracting(padMenuHeld)
            if pressed.contains(.up) { menuInput(.dpadUpPressed) }
            if pressed.contains(.down) { menuInput(.dpadDownPressed) }
            if pressed.contains(.a) { menuInput(.buttonAPressed) }
            if pressed.contains(.start) { menuInput(.buttonStartPressed) }
        case .gameOver:
            break
        }
        padMenuHeld = held
        if options { padMenuHeld.insert(.select) }
    }
}

// MARK: - Sound

/// The console's sound, pulled from the core by the audio thread.
final class GamePakAudio {
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private let lock = NSLock()
    private var source: GamePakMachine?
    private let scratch = UnsafeMutablePointer<Int16>.allocate(capacity: 16384)

    deinit {
        stop()
        scratch.deallocate()
    }

    func start(machine: GamePakMachine) {
        stop()
        lock.lock(); source = machine; lock.unlock()
        guard UserDefaults.standard.object(forKey: "soundOn") == nil || UserDefaults.standard.bool(forKey: "soundOn") else { return }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: machine.sampleRate, channels: 2) else { return }
        let buf = scratch
        let n = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, abl -> OSStatus in
            let list = UnsafeMutableAudioBufferListPointer(abl)
            let frames = Int(frameCount)
            var got = 0
            if let self {
                self.lock.lock()
                if let m = self.source { got = m.readAudio(buf, min(frames, 8192)) }
                self.lock.unlock()
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
        if let node { engine.detach(node) }
        node = nil
        lock.lock(); source = nil; lock.unlock()
    }
}
