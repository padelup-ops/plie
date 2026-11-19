// GamePakMachines.swift
// RetroCartridge
//
// The consoles behind the Game Pak: Game Boy / Color (SameBoy, linked in),
// Game Boy Advance (mGBA) and Nintendo DS (melonDS DS), the last two loaded
// from frameworks inside the app through a small libretro host (GBCore).

import CoreGraphics
import Foundation
import GBCore

/// A button of any of the consoles. GBA adds L and R; DS adds X, Y and the touch screen.
enum PakButton: CaseIterable {
    case up, down, left, right, a, b, x, y, l, r, start, select
}

protocol GamePakMachine: AnyObject {
    var frameTime: TimeInterval { get }
    var sampleRate: Double { get }
    /// The picture's size in pixels (for the layout and touch).
    var pixelSize: CGSize { get }
    var hasTouch: Bool { get }
    func runFrame()
    func makeImage() -> CGImage?
    func set(_ button: PakButton, _ down: Bool)
    func touch(x: Int, y: Int, pressed: Bool)
    func readAudio(_ out: UnsafeMutablePointer<Int16>, _ maxFrames: Int) -> Int
    func battery() -> Data?
    func loadBattery(_ data: Data)
    func state() -> Data?
    func loadState(_ data: Data)
    func close()
}

private func rgbxImage(_ px: UnsafePointer<UInt32>, width: Int, height: Int) -> CGImage? {
    let data = Data(bytes: px, count: width * height * 4)
    guard let provider = CGDataProvider(data: data as CFData) else { return nil }
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                   space: CGColorSpaceCreateDeviceRGB(),
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
}

// MARK: - Game Boy / Game Boy Color

final class SameBoyMachine: GamePakMachine {
    private var core: OpaquePointer?
    let sampleRate: Double = 48_000
    let frameTime: TimeInterval = 70224.0 / 4194304.0
    let pixelSize = CGSize(width: 160, height: 144)
    let hasTouch = false

    init?(rom: URL) {
        guard let data = try? Data(contentsOf: rom), let k = gbk_create(1, 48_000) else { return nil }
        core = k
        data.withUnsafeBytes { gbk_load_rom(k, $0.bindMemory(to: UInt8.self).baseAddress, data.count) }
    }

    deinit { close() }

    func runFrame() { if let core { gbk_run_frame(core) } }

    func makeImage() -> CGImage? {
        guard let core, let px = gbk_pixels(core) else { return nil }
        return rgbxImage(px, width: 160, height: 144)
    }

    func set(_ button: PakButton, _ down: Bool) {
        guard let core else { return }
        let key: Int
        switch button {
        case .up: key = Int(GBK_UP)
        case .down: key = Int(GBK_DOWN)
        case .left: key = Int(GBK_LEFT)
        case .right: key = Int(GBK_RIGHT)
        case .a: key = Int(GBK_A)
        case .b: key = Int(GBK_B)
        case .start: key = Int(GBK_START)
        case .select: key = Int(GBK_SELECT)
        default: return
        }
        gbk_set_key(core, Int32(key), down ? 1 : 0)
    }

    func touch(x: Int, y: Int, pressed: Bool) {}

    func readAudio(_ out: UnsafeMutablePointer<Int16>, _ maxFrames: Int) -> Int {
        guard let core else { return 0 }
        return Int(gbk_read_audio(core, out, maxFrames))
    }

    func battery() -> Data? {
        guard let core else { return nil }
        let n = gbk_battery_size(core)
        guard n > 0 else { return nil }
        var buf = Data(count: n)
        let written = buf.withUnsafeMutableBytes { gbk_battery_save(core, $0.bindMemory(to: UInt8.self).baseAddress, n) }
        return written > 0 ? buf.prefix(written) : nil
    }

    func loadBattery(_ data: Data) {
        guard let core else { return }
        data.withUnsafeBytes { gbk_battery_load(core, $0.bindMemory(to: UInt8.self).baseAddress, data.count) }
    }

    func state() -> Data? {
        guard let core else { return nil }
        let n = gbk_state_size(core)
        guard n > 0 else { return nil }
        var buf = Data(count: n)
        buf.withUnsafeMutableBytes { gbk_state_save(core, $0.bindMemory(to: UInt8.self).baseAddress) }
        return buf
    }

    func loadState(_ data: Data) {
        guard let core else { return }
        _ = data.withUnsafeBytes { gbk_state_load(core, $0.bindMemory(to: UInt8.self).baseAddress, data.count) }
    }

    func close() {
        if let core { gbk_destroy(core) }
        core = nil
    }
}

// MARK: - Game Boy Advance and DS (libretro cores in frameworks)

final class RetroCoreMachine: GamePakMachine {
    let frameTime: TimeInterval
    let sampleRate: Double
    let hasTouch: Bool
    private var open = false
    private(set) var pixelSize: CGSize

    /// Why the last start failed, for the library screen.
    static var lastError: String?

    init?(system: PakSystem, rom: URL, saveDir: URL) {
        let name = system == .nds ? "MelonDSCore" : "MGBACore"
        guard let fw = Bundle.main.privateFrameworksURL?.appendingPathComponent("\(name).framework/\(name)"),
              FileManager.default.fileExists(atPath: fw.path) else {
            Self.lastError = "\(name) missing"
            return nil
        }
        let sys = saveDir.appendingPathComponent("system", isDirectory: true)
        try? FileManager.default.createDirectory(at: sys, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        guard lr_open(fw.path, sys.path, saveDir.path) == 0 else {
            Self.lastError = String(cString: lr_error())
            return nil
        }
        guard lr_load(rom.path) == 0 else {
            Self.lastError = String(cString: lr_error())
            lr_close()
            return nil
        }
        open = true
        hasTouch = system == .nds
        frameTime = 1 / lr_fps()
        sampleRate = lr_sample_rate()
        pixelSize = system == .nds ? CGSize(width: 256, height: 384) : CGSize(width: 240, height: 160)
    }

    deinit { close() }

    func runFrame() { if open { lr_run_frame() } }

    func makeImage() -> CGImage? {
        guard open else { return nil }
        var w: Int32 = 0, h: Int32 = 0
        guard let px = lr_pixels(&w, &h), w > 0, h > 0 else { return nil }
        pixelSize = CGSize(width: Int(w), height: Int(h))
        return rgbxImage(px, width: Int(w), height: Int(h))
    }

    func set(_ button: PakButton, _ down: Bool) {
        let id: Int
        switch button {
        case .up: id = Int(LR_UP)
        case .down: id = Int(LR_DOWN)
        case .left: id = Int(LR_LEFT)
        case .right: id = Int(LR_RIGHT)
        case .a: id = Int(LR_A)
        case .b: id = Int(LR_B)
        case .x: id = Int(LR_X)
        case .y: id = Int(LR_Y)
        case .l: id = Int(LR_L)
        case .r: id = Int(LR_R)
        case .start: id = Int(LR_START)
        case .select: id = Int(LR_SELECT)
        }
        lr_set_button(Int32(id), down ? 1 : 0)
    }

    func touch(x: Int, y: Int, pressed: Bool) { lr_set_pointer(Int32(x), Int32(y), pressed ? 1 : 0) }

    func readAudio(_ out: UnsafeMutablePointer<Int16>, _ maxFrames: Int) -> Int {
        open ? Int(lr_read_audio(out, maxFrames)) : 0
    }

    func battery() -> Data? {
        guard open, let p = lr_sram() else { return nil }
        let n = lr_sram_size()
        return n > 0 ? Data(bytes: p, count: n) : nil
    }

    func loadBattery(_ data: Data) {
        guard open, let p = lr_sram() else { return }
        let n = min(lr_sram_size(), data.count)
        data.withUnsafeBytes { raw in
            if let base = raw.baseAddress { p.update(from: base.assumingMemoryBound(to: UInt8.self), count: n) }
        }
    }

    func state() -> Data? {
        guard open else { return nil }
        let n = lr_state_size()
        guard n > 0 else { return nil }
        var buf = Data(count: n)
        let ok = buf.withUnsafeMutableBytes { lr_state_save($0.bindMemory(to: UInt8.self).baseAddress, n) }
        return ok == 0 ? buf : nil
    }

    func loadState(_ data: Data) {
        guard open else { return }
        _ = data.withUnsafeBytes { lr_state_load($0.bindMemory(to: UInt8.self).baseAddress, data.count) }
    }

    func close() {
        if open { lr_close() }
        open = false
    }
}
