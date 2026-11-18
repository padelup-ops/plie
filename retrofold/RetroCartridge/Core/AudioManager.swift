//
//  AudioManager.swift
//  RetroCartridge
//
//  Synthesizes 8-bit sounds using AVAudioEngine for low-latency game sounds.
//
//  The synth is modeled loosely on a classic handheld sound chip: three
//  channels (lead pulse, effects pulse, noise), each playing one "patch" at a
//  time. A patch is a short sequence of notes (arpeggios, pitch sweeps, noise
//  bursts) that is sequenced sample-accurately on the CoreAudio thread.
//

import AVFoundation
import Observation
import os

// MARK: - Synth Building Blocks

/// Oscillator shapes, modeled on classic 8-bit sound chips.
enum Waveform: Sendable {
    /// 50% duty pulse: full, hollow tone.
    case square
    /// 25% duty pulse: thinner, nasal tone.
    case pulse25
    /// 12.5% duty pulse: buzzy, bright tone.
    case pulse12
    /// Stepless triangle: soft, bass-like tone.
    case triangle
    /// 15-bit LFSR noise; the frequency sets the shift-register clock rate.
    case noise
}

/// One step of a patch. Pitch glides exponentially from `startHz` to `endHz`.
struct SynthNote: Sendable {
    var startHz: Double
    var endHz: Double
    var durationMs: Double
    var waveform: Waveform
    var volume: Double
    /// Percussive notes fade linearly to silence over their duration.
    var decays: Bool = false
    /// Legato notes run straight into the next note without a release gap.
    var legato: Bool = false

    /// A steady note.
    static func tone(_ hz: Double, _ ms: Double, _ waveform: Waveform = .square, volume: Double = 0.4, decays: Bool = false) -> SynthNote {
        SynthNote(startHz: hz, endHz: hz, durationMs: ms, waveform: waveform, volume: volume, decays: decays)
    }

    /// A pitch sweep (or noise-rate sweep), percussive by default.
    static func sweep(_ fromHz: Double, _ toHz: Double, _ ms: Double, _ waveform: Waveform = .square, volume: Double = 0.4, decays: Bool = true, legato: Bool = false) -> SynthNote {
        SynthNote(startHz: fromHz, endHz: toHz, durationMs: ms, waveform: waveform, volume: volume, decays: decays, legato: legato)
    }

    /// Silence.
    static func rest(_ ms: Double) -> SynthNote {
        SynthNote(startHz: 440, endHz: 440, durationMs: ms, waveform: .square, volume: 0)
    }
}

/// The synth's channels. Each plays one patch at a time.
enum SynthChannel: Int, CaseIterable, Sendable {
    /// Jingles and melodic cues.
    case lead
    /// Short blips: bounces, ticks, hits.
    case effects
    /// Noise channel: crashes, thuds, shimmer.
    case noise
    /// Music melody (`ChipMusic`), apart from the effects so they never cut it off.
    case musicLead
    /// Music bass.
    case musicBass
    /// Music drums (noise).
    case musicDrums

    /// The channels music plays on.
    static let music: [SynthChannel] = [.musicLead, .musicBass, .musicDrums]
}

/// A playable sound: a note sequence bound to a channel.
///
/// A new patch replaces whatever its channel is playing unless the playing
/// patch has a higher priority, so small blips never cut off a jingle.
struct SynthPatchDefinition: Sendable {
    var channel: SynthChannel
    var priority: Int
    var notes: [SynthNote]
    /// Looping patches start over from their first note until stopped (music).
    var loops: Bool = false
}

// MARK: - Note Names

/// Equal-tempered pitches used by the patches, in Hz.
private enum Pitch {
    static let c3 = 130.81, g3 = 196.00
    static let c4 = 261.63, e4 = 329.63, ds4 = 311.13, f4 = 349.23, fs4 = 369.99, g4 = 392.00, a4 = 440.00
    static let c5 = 523.25, e5 = 659.25, g5 = 783.99, a5 = 880.00
    static let c6 = 1046.50, e6 = 1318.51, g6 = 1567.98
    static let c7 = 2093.00, e7 = 2637.02
}

// MARK: - Patches

/// Every sound the synth can play. The note table is built once at launch
/// and handed to the audio thread, so triggering a sound is just an index.
enum SynthPatch: Int, CaseIterable, Sendable {
    // System
    case startupChime
    case cartridgeClick, cartridgeClickNoise
    case hingeSnap

    // Shared game cues
    case roundStart
    case levelUp
    case gameOver
    case powerUp
    case collisionTone, collisionNoise

    // Brick Breaker
    case paddleBounce, wallBounce, brickBreak
    case lifeLostTone, lifeLostNoise
    case laserShot, armorHit

    // Snake
    case eat
    case bonus

    // Retro Racer
    case laneChange
    case crashTone, crashNoise
    case coin

    // Falling Blocks
    case moveTick, rotate
    case pieceLockTone, pieceLockNoise
    case hardDropTone, hardDropNoise
    case lineClear1, lineClear2, lineClear3
    case lineClear4Lead, lineClear4Harmony, lineClear4Shimmer

    // Pixel Invaders
    case march1, march2, march3, march4
    case explosionTone, explosionNoise

    // Mine Sweep
    case reveal, flag

    // Maze Muncher
    case chomp

    // Frog Hop
    case hop

    // Lunar Hinge
    case thrust

    var definition: SynthPatchDefinition {
        switch self {
        // MARK: System
        case .startupChime:
            return SynthPatchDefinition(channel: .lead, priority: 3, notes: [
                .tone(Pitch.c4, 100), .tone(Pitch.e4, 100), .tone(Pitch.g4, 100), .tone(Pitch.c5, 180, decays: true)
            ])
        case .cartridgeClick:
            return SynthPatchDefinition(channel: .effects, priority: 2, notes: [
                .sweep(140, 80, 50, .square, volume: 0.4)
            ])
        case .cartridgeClickNoise:
            return SynthPatchDefinition(channel: .noise, priority: 2, notes: [
                .tone(9000, 25, .noise, volume: 0.25, decays: true)
            ])
        case .hingeSnap:
            return SynthPatchDefinition(channel: .effects, priority: 2, notes: [
                .sweep(180, 90, 40, .triangle, volume: 0.6)
            ])

        // MARK: Shared game cues
        case .roundStart:
            // Quick "ready, go!" run up the C major triad. Top priority, since
            // the player asked for it (it may cut off a game-over tune).
            return SynthPatchDefinition(channel: .lead, priority: 6, notes: [
                .tone(Pitch.g4, 60, .pulse25), .tone(Pitch.c5, 60, .pulse25), .tone(Pitch.e5, 60, .pulse25),
                .tone(Pitch.g5, 60, .pulse25), .tone(Pitch.c6, 180, .pulse25, decays: true)
            ])
        case .levelUp:
            return SynthPatchDefinition(channel: .lead, priority: 4, notes: [
                .tone(Pitch.c5, 80), .tone(Pitch.e5, 80), .tone(Pitch.g5, 80), .tone(Pitch.c6, 80),
                .tone(Pitch.g5, 80), .tone(Pitch.c6, 260, decays: true)
            ])
        case .gameOver:
            // Descending "wah-wah-wah-waaah".
            return SynthPatchDefinition(channel: .lead, priority: 5, notes: [
                .rest(120),
                .tone(Pitch.g4, 220), .tone(Pitch.fs4, 220), .tone(Pitch.f4, 220),
                .sweep(Pitch.e4, Pitch.ds4 * 0.97, 650, .square, volume: 0.4)
            ])
        case .powerUp:
            return SynthPatchDefinition(channel: .lead, priority: 3, notes: [
                .tone(Pitch.c5, 35, .pulse25), .tone(Pitch.e5, 35, .pulse25), .tone(Pitch.g5, 35, .pulse25),
                .tone(Pitch.c6, 35, .pulse25), .tone(Pitch.e6, 35, .pulse25), .tone(Pitch.g6, 35, .pulse25),
                .tone(Pitch.c7, 90, .pulse25, decays: true)
            ])
        case .collisionTone:
            return SynthPatchDefinition(channel: .effects, priority: 3, notes: [
                .sweep(220, 55, 160, .square, volume: 0.45)
            ])
        case .collisionNoise:
            return SynthPatchDefinition(channel: .noise, priority: 3, notes: [
                .sweep(2000, 300, 140, .noise, volume: 0.35)
            ])

        // MARK: Brick Breaker
        case .paddleBounce:
            return SynthPatchDefinition(channel: .effects, priority: 1, notes: [
                .tone(Pitch.a4, 45, .pulse25, volume: 0.4, decays: true)
            ])
        case .wallBounce:
            return SynthPatchDefinition(channel: .effects, priority: 0, notes: [
                .tone(Pitch.e4, 25, .pulse25, volume: 0.2, decays: true)
            ])
        case .brickBreak:
            return SynthPatchDefinition(channel: .effects, priority: 2, notes: [
                .sweep(Pitch.c6, Pitch.g5, 60, .pulse12, volume: 0.35)
            ])
        case .lifeLostTone:
            return SynthPatchDefinition(channel: .lead, priority: 3, notes: [
                .sweep(Pitch.g5, 90, 520, .square, volume: 0.4)
            ])
        case .lifeLostNoise:
            return SynthPatchDefinition(channel: .noise, priority: 3, notes: [
                .sweep(3000, 500, 260, .noise, volume: 0.3)
            ])

        case .laserShot:
            return SynthPatchDefinition(channel: .effects, priority: 1, notes: [
                .sweep(1800, 600, 60, .pulse12, volume: 0.25)
            ])
        case .armorHit:
            // A dull metallic clink
            return SynthPatchDefinition(channel: .effects, priority: 2, notes: [
                .sweep(1400, 900, 40, .pulse25, volume: 0.3)
            ])

        // MARK: Snake
        case .eat:
            return SynthPatchDefinition(channel: .effects, priority: 2, notes: [
                .sweep(Pitch.c5, Pitch.c6, 45, .pulse25, volume: 0.35, decays: false, legato: true),
                .tone(Pitch.g6, 40, .pulse25, volume: 0.3, decays: true)
            ])

        case .bonus:
            // A bright four-note run for the bonus food
            return SynthPatchDefinition(channel: .lead, priority: 3, notes: [
                .tone(Pitch.e5, 40, .pulse25), .tone(Pitch.g5, 40, .pulse25),
                .tone(Pitch.c6, 40, .pulse25), .tone(Pitch.e6, 90, .pulse25, decays: true)
            ])

        // MARK: Retro Racer
        case .laneChange:
            return SynthPatchDefinition(channel: .effects, priority: 1, notes: [
                .sweep(Pitch.a4, Pitch.e5, 40, .pulse12, volume: 0.25)
            ])
        case .crashTone:
            return SynthPatchDefinition(channel: .effects, priority: 4, notes: [
                .sweep(330, 40, 420, .square, volume: 0.35)
            ])
        case .crashNoise:
            return SynthPatchDefinition(channel: .noise, priority: 4, notes: [
                .sweep(5000, 150, 750, .noise, volume: 0.5)
            ])

        case .coin:
            // The classic two-note coin
            return SynthPatchDefinition(channel: .effects, priority: 2, notes: [
                .tone(Pitch.g5 * 1.26, 45, .square, volume: 0.3), .tone(Pitch.e6 * 1.19, 140, .square, volume: 0.3, decays: true)
            ])

        // MARK: Falling Blocks
        case .moveTick:
            return SynthPatchDefinition(channel: .effects, priority: 0, notes: [
                .tone(Pitch.e6, 14, .pulse12, volume: 0.15)
            ])
        case .rotate:
            return SynthPatchDefinition(channel: .effects, priority: 1, notes: [
                .sweep(Pitch.a5, Pitch.e6, 30, .pulse25, volume: 0.2)
            ])
        case .pieceLockTone:
            return SynthPatchDefinition(channel: .effects, priority: 2, notes: [
                .sweep(Pitch.g3, Pitch.c3, 50, .square, volume: 0.35)
            ])
        case .pieceLockNoise:
            return SynthPatchDefinition(channel: .noise, priority: 2, notes: [
                .tone(1500, 35, .noise, volume: 0.2, decays: true)
            ])
        case .hardDropTone:
            return SynthPatchDefinition(channel: .effects, priority: 3, notes: [
                .sweep(Pitch.c6, Pitch.c3, 90, .square, volume: 0.35)
            ])
        case .hardDropNoise:
            return SynthPatchDefinition(channel: .noise, priority: 3, notes: [
                .sweep(2500, 400, 100, .noise, volume: 0.35)
            ])
        case .lineClear1:
            return SynthPatchDefinition(channel: .lead, priority: 3, notes: [
                .tone(Pitch.c6, 50, .pulse25), .tone(Pitch.e6, 50, .pulse25), .tone(Pitch.g6, 110, .pulse25, decays: true)
            ])
        case .lineClear2:
            return SynthPatchDefinition(channel: .lead, priority: 3, notes: [
                .tone(Pitch.c6, 50, .pulse25), .tone(Pitch.e6, 50, .pulse25), .tone(Pitch.g6, 50, .pulse25),
                .tone(Pitch.c7, 130, .pulse25, decays: true)
            ])
        case .lineClear3:
            return SynthPatchDefinition(channel: .lead, priority: 3, notes: [
                .tone(Pitch.c6, 50, .pulse25), .tone(Pitch.e6, 50, .pulse25), .tone(Pitch.g6, 50, .pulse25),
                .tone(Pitch.c7, 50, .pulse25), .tone(Pitch.e7, 150, .pulse25, decays: true)
            ])
        case .lineClear4Lead:
            // Four-line clear: a full two-octave fanfare over a harmony and a noise shimmer.
            return SynthPatchDefinition(channel: .lead, priority: 5, notes: [
                .tone(Pitch.c5, 55), .tone(Pitch.e5, 55), .tone(Pitch.g5, 55), .tone(Pitch.c6, 55),
                .tone(Pitch.e6, 55), .tone(Pitch.g6, 55), .tone(Pitch.c7, 55),
                .tone(Pitch.g6, 70), .tone(Pitch.c7, 320, decays: true)
            ])
        case .lineClear4Harmony:
            return SynthPatchDefinition(channel: .effects, priority: 5, notes: [
                .tone(Pitch.g4, 55, .pulse12, volume: 0.25), .tone(Pitch.c5, 55, .pulse12, volume: 0.25),
                .tone(Pitch.e5, 55, .pulse12, volume: 0.25), .tone(Pitch.g5, 55, .pulse12, volume: 0.25),
                .tone(Pitch.c6, 55, .pulse12, volume: 0.25), .tone(Pitch.e6, 55, .pulse12, volume: 0.25),
                .tone(Pitch.g6, 55, .pulse12, volume: 0.25),
                .tone(Pitch.e6, 70, .pulse12, volume: 0.25), .tone(Pitch.g6, 320, .pulse12, volume: 0.25, decays: true)
            ])
        case .lineClear4Shimmer:
            return SynthPatchDefinition(channel: .noise, priority: 5, notes: [
                .rest(385),
                .tone(12000, 400, .noise, volume: 0.15, decays: true)
            ])

        // MARK: Pixel Invaders
        case .march1, .march2, .march3, .march4:
            // The descending four-note bass march
            let notes = [98.0, 87.31, 77.78, 73.42]
            let index = rawValue - SynthPatch.march1.rawValue
            return SynthPatchDefinition(channel: .effects, priority: 0, notes: [
                .tone(notes[index], 70, .triangle, volume: 0.55, decays: true)
            ])
        case .explosionTone:
            return SynthPatchDefinition(channel: .effects, priority: 2, notes: [
                .sweep(600, 120, 120, .pulse12, volume: 0.3)
            ])
        case .explosionNoise:
            return SynthPatchDefinition(channel: .noise, priority: 2, notes: [
                .sweep(4000, 800, 180, .noise, volume: 0.35)
            ])

        // MARK: Mine Sweep
        case .reveal:
            return SynthPatchDefinition(channel: .effects, priority: 1, notes: [
                .sweep(Pitch.c5, Pitch.g5, 35, .pulse25, volume: 0.25)
            ])
        case .flag:
            return SynthPatchDefinition(channel: .effects, priority: 1, notes: [
                .tone(Pitch.g5, 30, .square, volume: 0.25), .tone(Pitch.c6, 50, .square, volume: 0.25, decays: true)
            ])

        // MARK: Maze Muncher
        case .chomp:
            return SynthPatchDefinition(channel: .effects, priority: 0, notes: [
                .sweep(Pitch.g4, Pitch.c4, 45, .triangle, volume: 0.45, decays: false, legato: true),
                .sweep(Pitch.c4, Pitch.g4, 45, .triangle, volume: 0.45)
            ])

        // MARK: Frog Hop
        case .hop:
            return SynthPatchDefinition(channel: .effects, priority: 1, notes: [
                .sweep(Pitch.e5, Pitch.a5, 40, .pulse25, volume: 0.25)
            ])

        // MARK: Lunar Hinge
        case .thrust:
            return SynthPatchDefinition(channel: .noise, priority: 0, notes: [
                .tone(600, 150, .noise, volume: 0.18, decays: true)
            ])
        }
    }
}

// MARK: - Sound Packs

/// Alternative voicings of every sound, like swapping the sound chip. A
/// pack rewrites each patch's notes (waveform, pitch, length, volume); all
/// packs are built into the note table at launch, so switching packs is
/// just a different patch index and the audio thread is untouched.
enum SoundPack: String, CaseIterable, Identifiable, Codable, Sendable {
    /// The original sounds.
    case classic
    /// Thin pulse waves, like a monochrome handheld.
    case pocket
    /// Lower and punchier, like an arcade cabinet.
    case arcade
    /// Soft triangle tones throughout.
    case mellow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return String(localized: "Classic", comment: "Sound pack name")
        case .pocket: return String(localized: "Pocket", comment: "Sound pack name")
        case .arcade: return String(localized: "Arcade", comment: "Sound pack name")
        case .mellow: return String(localized: "Mellow", comment: "Sound pack name")
        }
    }

    /// The IAP product that unlocks the pack, nil when it is free.
    var requiredProductID: String? {
        self == .classic ? nil : ProductIdentifiers.pro
    }

    /// A patch as this pack voices it. Looping patches (music) keep their
    /// note lengths, so their parts stay in step.
    func voice(_ patch: SynthPatchDefinition) -> SynthPatchDefinition {
        var voiced = patch
        voiced.notes = patch.notes.map { note in
            var result = voiceNote(note)
            if patch.loops {
                result.durationMs = note.durationMs
            }
            return result
        }
        return voiced
    }

    private func voiceNote(_ note: SynthNote) -> SynthNote {
        var voiced = note
        switch self {
        case .classic:
            break
        case .pocket:
            switch note.waveform {
            case .square: voiced.waveform = .pulse25
            case .pulse25: voiced.waveform = .pulse12
            default: break
            }
            voiced.volume = note.volume * 0.9
        case .arcade:
            if note.waveform != .noise {
                voiced.waveform = .square
                // Down three semitones
                voiced.startHz = note.startHz * 0.84
                voiced.endHz = note.endHz * 0.84
            }
            voiced.durationMs = note.durationMs * 1.1
        case .mellow:
            if note.waveform == .noise {
                voiced.volume = note.volume * 0.6
            } else {
                voiced.waveform = .triangle
                voiced.volume = min(0.7, note.volume * 1.15)
            }
        }
        return voiced
    }
}

// MARK: - Tone Generator

/// Thread-safe synthesizer running on the realtime CoreAudio thread.
/// Completely nonisolated from any actor.
///
/// Real-time safety: every buffer is allocated in `init`. The render callback
/// never allocates, and only takes `lock` briefly to pick up the mute flag and
/// any patches triggered since the previous buffer. Voice state is owned by the
/// audio thread alone, and the note table is immutable after `init`.
final class ToneGenerator: @unchecked Sendable {

    // MARK: Render Data

    /// A note converted to per-sample units.
    private struct RenderNote {
        var frames: Int
        /// Oscillator cycles per sample at the start of the note.
        var startIncrement: Double
        /// Per-sample multiplier on the increment (exponential glide).
        var incrementRatio: Double
        var waveform: Waveform
        var volume: Double
        var decays: Bool
        /// Frames at the end of the note during which the gate is closed.
        var releaseFrames: Int
    }

    /// A patch's slice of the note table.
    private struct PatchRange {
        var firstNote: Int
        var noteCount: Int
        var channel: Int
        var priority: Int
        var loops: Bool
    }

    /// Playback state of one channel. Only touched on the audio thread.
    private struct Voice {
        var isActive = false
        var priority = 0
        var noteIndex = 0
        var noteEnd = 0
        var frameInNote = 0
        var increment = 0.0
        var phase = 0.0
        /// Smoothed output gain; slews toward the envelope to avoid clicks.
        var gain = 0.0
        var lfsr: UInt16 = 1
        var noiseLevel = 1.0
        /// Looping voices go back to `loopStart` after their last note.
        var loops = false
        var loopStart = 0
    }

    // MARK: Constants

    private let sampleRate: Double
    private let channelCount = SynthChannel.allCases.count
    private let pendingCapacity = 16
    /// Overall output level; three full voices come close to full scale,
    /// and the limiter rounds off anything louder.
    private let masterGain = 0.75
    /// Per-sample gain slew coefficient (~1 ms time constant).
    private let gainSlew: Double

    // MARK: Storage (allocated once)

    private let lock: os_unfair_lock_t
    private let notes: UnsafeMutableBufferPointer<RenderNote>
    private let patches: UnsafeMutableBufferPointer<PatchRange>
    private let voices: UnsafeMutableBufferPointer<Voice>
    /// Triggers queued by the main thread. Guarded by `lock`.
    private let pending: UnsafeMutableBufferPointer<Int>
    private var pendingCount = 0
    /// Audio-thread copy of `pending`, taken under the lock.
    private let incoming: UnsafeMutableBufferPointer<Int>
    /// Guarded by `lock`.
    private var muted = false

    // MARK: Lifecycle

    init(patches definitions: [SynthPatchDefinition], sampleRate: Double) {
        self.sampleRate = sampleRate
        self.gainSlew = 1.0 - exp(-1.0 / (0.001 * sampleRate))

        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())

        let totalNotes = definitions.reduce(0) { $0 + $1.notes.count }
        notes = .allocate(capacity: max(totalNotes, 1))
        patches = .allocate(capacity: max(definitions.count, 1))
        voices = .allocate(capacity: channelCount)
        voices.initialize(repeating: Voice())
        pending = .allocate(capacity: pendingCapacity)
        pending.initialize(repeating: 0)
        incoming = .allocate(capacity: pendingCapacity)
        incoming.initialize(repeating: 0)

        let releaseCap = Int(0.004 * sampleRate)
        var noteCursor = 0
        for (patchIndex, definition) in definitions.enumerated() {
            patches.initializeElement(at: patchIndex, to: PatchRange(
                firstNote: noteCursor,
                noteCount: definition.notes.count,
                channel: definition.channel.rawValue,
                priority: definition.priority,
                loops: definition.loops
            ))
            for (i, note) in definition.notes.enumerated() {
                // Rounded, not truncated, so music notes land on whole samples
                let frames = max(1, Int((note.durationMs / 1000.0 * sampleRate).rounded()))
                let startIncrement = note.startHz / sampleRate
                let endIncrement = note.endHz / sampleRate
                // The last note always releases, so a patch never ends on an open gate.
                let isLast = i == definition.notes.count - 1
                let releases = !note.legato || isLast
                notes.initializeElement(at: noteCursor, to: RenderNote(
                    frames: frames,
                    startIncrement: startIncrement,
                    incrementRatio: pow(endIncrement / startIncrement, 1.0 / Double(frames)),
                    waveform: note.waveform,
                    volume: note.volume,
                    decays: note.decays,
                    releaseFrames: releases ? min(releaseCap, frames / 3) : 0
                ))
                noteCursor += 1
            }
        }
    }

    deinit {
        notes.deallocate()
        patches.deallocate()
        voices.deallocate()
        pending.deallocate()
        incoming.deallocate()
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    // MARK: Control (any thread)

    /// Silences the output while true.
    var isMuted: Bool {
        get {
            os_unfair_lock_lock(lock)
            defer { os_unfair_lock_unlock(lock) }
            return muted
        }
        set {
            os_unfair_lock_lock(lock)
            muted = newValue
            os_unfair_lock_unlock(lock)
        }
    }

    /// Queues a stop: the channel's voice fades out at the next buffer.
    func stop(channel: Int) {
        guard channel >= 0, channel < channelCount else { return }
        os_unfair_lock_lock(lock)
        if pendingCount < pendingCapacity {
            // Stops travel in the same queue as negative entries
            pending[pendingCount] = -(channel + 1)
            pendingCount += 1
        }
        os_unfair_lock_unlock(lock)
    }

    /// Queues a patch to start at the beginning of the next render buffer.
    func trigger(patchIndex: Int) {
        guard patchIndex >= 0, patchIndex < patches.count else { return }
        os_unfair_lock_lock(lock)
        if pendingCount < pendingCapacity {
            pending[pendingCount] = patchIndex
            pendingCount += 1
        }
        os_unfair_lock_unlock(lock)
    }

    // MARK: Rendering (audio thread)

    func render(frameCount: AVAudioFrameCount, audioBufferList: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)

        // Pick up shared state, then render without holding the lock.
        os_unfair_lock_lock(lock)
        let isSilenced = muted
        let triggerCount = pendingCount
        for i in 0..<triggerCount {
            incoming[i] = pending[i]
        }
        pendingCount = 0
        os_unfair_lock_unlock(lock)

        for i in 0..<triggerCount {
            let entry = incoming[i]
            if entry < 0 {
                // The gain slews down, so stopping doesn't click
                let channel = -(entry + 1)
                voices[channel].isActive = false
            } else {
                start(patch: patches[entry])
            }
        }

        for frame in 0..<Int(frameCount) {
            var mix = 0.0
            for channel in 0..<channelCount {
                mix += nextSample(voice: &voices[channel])
            }
            let sample = isSilenced ? 0 : Float(Self.limit(mix * masterGain))

            for buffer in ablPointer {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                data[frame] = sample
            }
        }

        return noErr
    }

    /// Where the limiter starts bending the signal. Music and single effects
    /// peak around 0.5, so they pass through untouched.
    static let limiterKnee = 0.8

    /// A soft limiter: passes the signal through up to `limiterKnee`, then
    /// bends it smoothly toward full scale, which it never reaches. Loud
    /// moments (a crash and the game-over tune over the music) would
    /// otherwise clip flat and crackle. No allocation: safe on the audio thread.
    @inline(__always)
    static func limit(_ sample: Double) -> Double {
        let magnitude = abs(sample)
        guard magnitude > limiterKnee else { return sample }
        let headroom = 1 - limiterKnee
        let bent = limiterKnee + headroom * tanh((magnitude - limiterKnee) / headroom)
        return sample < 0 ? -bent : bent
    }

    /// Starts a patch on its channel unless a higher-priority patch is playing there.
    private func start(patch: PatchRange) {
        guard patch.noteCount > 0 else { return }
        var voice = voices[patch.channel]
        if voice.isActive && voice.priority > patch.priority { return }

        // Phase and gain carry over so the switch is continuous.
        voice.isActive = true
        voice.priority = patch.priority
        voice.noteIndex = patch.firstNote
        voice.noteEnd = patch.firstNote + patch.noteCount
        voice.loops = patch.loops
        voice.loopStart = patch.firstNote
        voice.frameInNote = 0
        voice.increment = notes[patch.firstNote].startIncrement
        voices[patch.channel] = voice
    }

    /// Advances one voice by one sample and returns its output.
    private func nextSample(voice: inout Voice) -> Double {
        var target = 0.0
        var waveform = Waveform.square

        if voice.isActive {
            let note = notes[voice.noteIndex]
            waveform = note.waveform

            // Envelope: gate closes for the release tail; percussive notes fade out.
            if voice.frameInNote < note.frames - note.releaseFrames {
                target = note.volume
                if note.decays {
                    target *= 1.0 - Double(voice.frameInNote) / Double(note.frames)
                }
            }

            voice.frameInNote += 1
            if voice.frameInNote >= note.frames {
                voice.noteIndex += 1
                voice.frameInNote = 0
                if voice.noteIndex >= voice.noteEnd && voice.loops {
                    voice.noteIndex = voice.loopStart
                    voice.increment = notes[voice.noteIndex].startIncrement
                } else if voice.noteIndex >= voice.noteEnd {
                    voice.isActive = false
                } else {
                    voice.increment = notes[voice.noteIndex].startIncrement
                }
            } else {
                voice.increment *= note.incrementRatio
            }
        } else if voice.gain < 1e-5 {
            voice.gain = 0
            return 0
        }

        // Oscillator
        voice.phase += voice.increment
        var oscillator: Double
        switch waveform {
        case .noise:
            while voice.phase >= 1.0 {
                voice.phase -= 1.0
                // NES-style 15-bit linear-feedback shift register.
                let feedback = (voice.lfsr ^ (voice.lfsr >> 1)) & 1
                voice.lfsr = (voice.lfsr >> 1) | (feedback << 14)
                voice.noiseLevel = (voice.lfsr & 1) == 0 ? 1.0 : -1.0
            }
            oscillator = voice.noiseLevel
        case .square, .pulse25, .pulse12, .triangle:
            if voice.phase >= 1.0 {
                voice.phase -= voice.phase.rounded(.down)
            }
            switch waveform {
            case .square: oscillator = voice.phase < 0.5 ? 1.0 : -1.0
            case .pulse25: oscillator = voice.phase < 0.25 ? 1.0 : -1.0
            case .pulse12: oscillator = voice.phase < 0.125 ? 1.0 : -1.0
            default: oscillator = voice.phase < 0.5 ? 4.0 * voice.phase - 1.0 : 3.0 - 4.0 * voice.phase
            }
        }

        voice.gain += (target - voice.gain) * gainSlew
        return oscillator * voice.gain
    }
}

/// Standalone nonisolated factory for the AVAudioSourceNode so no actor context is captured.
private nonisolated func makeSourceNode(generator: ToneGenerator) -> AVAudioSourceNode {
    return AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
        return generator.render(frameCount: frameCount, audioBufferList: audioBufferList)
    }
}

// MARK: - Audio Manager

@Observable
final class AudioManager: @unchecked Sendable {

    private static let sampleRate: Double = 44100.0

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var sourceNode: AVAudioSourceNode?
    /// One sound pack's patches: every sound effect, then every cartridge's
    /// music (`ChipMusic.partsPerTrack` patches per cartridge).
    private static let patchTable: [SynthPatchDefinition] =
        SynthPatch.allCases.map(\.definition)
        + GameType.allCases.flatMap { ChipMusic.patches(for: ChipMusic.track(for: $0)) }

    /// Every patch in every sound pack, pack by pack.
    @ObservationIgnored private let generator = ToneGenerator(
        patches: SoundPack.allCases.flatMap { pack in AudioManager.patchTable.map { pack.voice($0) } },
        sampleRate: AudioManager.sampleRate
    )

    /// The voicing used for game sounds and music. Set from the main thread.
    @ObservationIgnored var soundPack: SoundPack = .classic {
        didSet {
            // Restart the music in the new voice
            if soundPack != oldValue, let music = currentMusic {
                currentMusic = nil
                playMusic(for: music)
            }
        }
    }

    /// The cartridge whose music is playing, nil for silence.
    @ObservationIgnored private var currentMusic: GameType?

    /// Where the current sound pack's patches start in the generator.
    private var packOffset: Int {
        (SoundPack.allCases.firstIndex(of: soundPack) ?? 0) * Self.patchTable.count
    }
    /// Serial queue for audio session and engine calls that can block, kept
    /// off the main thread. The engine is only started or stopped on it.
    @ObservationIgnored private let audioQueue = DispatchQueue(label: "RetroCartridge.AudioManager", qos: .userInitiated)

    var isMuted: Bool {
        get { generator.isMuted }
        set { generator.isMuted = newValue }
    }

    /// Whether sound effects play; the music has its own switch. Set from the
    /// main thread (from `AppState.isSoundOn`), and only read there.
    @ObservationIgnored var areSoundEffectsOn = true

    init() {
        setupAudio()
    }

    // MARK: - Setup

    private func setupAudio() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1) else {
            return
        }

        let node = makeSourceNode(generator: generator)
        self.sourceNode = node

        engine.attach(node)
        try? engine.connectNode(node, to: engine.mainMixerNode, format: format)

        // Activating the session can block for a while, so it and the engine
        // start (which depends on it) run on the audio queue.
        audioQueue.async { [self] in
            configureAudioSession()
            startEngineIfNeeded()
        }
    }

    /// Must be called on `audioQueue`.
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, mode: .default)
            try session.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }

    /// Must be called on `audioQueue`.
    private func startEngineIfNeeded() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    // MARK: - Playback

    /// Plays patches together in the current sound pack, starting on the
    /// next audio buffer.
    private func play(_ patches: SynthPatch...) {
        guard !isMuted, areSoundEffectsOn else { return }
        for patch in patches {
            generator.trigger(patchIndex: packOffset + patch.rawValue)
        }
        // Restart the engine if an interruption or route change stopped it.
        audioQueue.async { [self] in
            startEngineIfNeeded()
        }
    }

    // MARK: - Music

    /// Loops a cartridge's theme, or stops the music for nil. Cheap to call
    /// every frame: it only acts when the choice changes.
    func playMusic(for game: GameType?) {
        guard game != currentMusic else { return }
        currentMusic = game

        guard let game, let index = GameType.allCases.firstIndex(of: game) else {
            for channel in SynthChannel.music {
                generator.stop(channel: channel.rawValue)
            }
            return
        }

        // All three parts start on the same buffer, so they play in step
        let first = packOffset + SynthPatch.allCases.count + index * ChipMusic.partsPerTrack
        for part in 0..<ChipMusic.partsPerTrack {
            generator.trigger(patchIndex: first + part)
        }
        audioQueue.async { [self] in
            startEngineIfNeeded()
        }
    }

    func playStartupChime() {
        play(.startupChime)
    }

    func playCartridgeClick() {
        play(.cartridgeClick, .cartridgeClickNoise)
    }

    func playHingeSnap() {
        play(.hingeSnap)
    }

    func playGameSound(_ sound: GameSound) {
        switch sound {
        case .roundStart: play(.roundStart)
        case .levelUp: play(.levelUp)
        case .gameOver: play(.gameOver)
        case .powerUp: play(.powerUp)
        case .collision: play(.collisionTone, .collisionNoise)
        case .paddleBounce: play(.paddleBounce)
        case .wallBounce: play(.wallBounce)
        case .brickBreak: play(.brickBreak)
        case .lifeLost: play(.lifeLostTone, .lifeLostNoise)
        case .laserShot: play(.laserShot)
        case .armorHit: play(.armorHit)
        case .eat: play(.eat)
        case .bonus: play(.bonus)
        case .laneChange: play(.laneChange)
        case .crash: play(.crashTone, .crashNoise)
        case .coin: play(.coin)
        case .moveTick: play(.moveTick)
        case .rotate: play(.rotate)
        case .pieceLock: play(.pieceLockTone, .pieceLockNoise)
        case .hardDrop: play(.hardDropTone, .hardDropNoise)
        case .lineClear(let lines):
            switch lines {
            case ...1: play(.lineClear1)
            case 2: play(.lineClear2)
            case 3: play(.lineClear3)
            default: play(.lineClear4Lead, .lineClear4Harmony, .lineClear4Shimmer)
            }
        case .march(let step):
            let beats: [SynthPatch] = [.march1, .march2, .march3, .march4]
            play(beats[((step % 4) + 4) % 4])
        case .explosion: play(.explosionTone, .explosionNoise)
        case .reveal: play(.reveal)
        case .flag: play(.flag)
        case .chomp: play(.chomp)
        case .hop: play(.hop)
        case .thrust: play(.thrust)
        }
    }
}
