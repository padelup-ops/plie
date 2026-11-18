// ChipMusic.swift
// RetroCartridge
//
// A theme for every cartridge, played in a loop while it's inserted: a
// lead, a triangle bass and a noise drum kit, each on its own synth channel
// so sound effects never cut the music off. Scores are written as text
// ("E5:0.5" is E5 for half a beat, "-" a rest, "|" a bar line) and turned
// into looping patches once, at launch.
//
// Tempos are chosen so a sixteenth note is a whole number of samples at
// 44.1 kHz (661500 / bpm is an integer), so the three parts of a track
// stay in step however long they loop.

import Foundation

// MARK: - Track

struct ChipTrack: Sendable {
    let bpm: Int
    let leadWaveform: Waveform
    /// Melody score.
    let lead: String
    /// Bass score, played on a triangle wave.
    let bass: String
    /// One bar of drums, a character per sixteenth: `k` kick, `s` snare,
    /// `h` hi-hat, `.` rest. Repeated for every bar.
    let drumBar: String
    let bars: Int
}

// MARK: - Library

enum ChipMusic {

    /// The patches per track: lead, bass and drums.
    static let partsPerTrack = 3

    /// Samples per second the scores are written for (the synth's rate).
    static let sampleRate = 44_100.0

    static func track(for game: GameType) -> ChipTrack {
        switch game {
        case .brickBreaker:
            // bright C major bounce
            return ChipTrack(
                bpm: 150,
                leadWaveform: .pulse25,
                lead: "C5:0.5 E5:0.5 G5:0.5 C6:0.5 B5:0.5 G5:0.5 E5:1 | F5:0.5 A5:0.5 C6:0.5 A5:0.5 G5:1 -:1 | E5:0.5 G5:0.5 C6:0.5 E6:0.5 D6:0.5 C6:0.5 B5:1 | A5:0.5 G5:0.5 F5:0.5 D5:0.5 G5:1 -:1 | C5:0.5 E5:0.5 G5:0.5 C6:0.5 B5:0.5 G5:0.5 E5:1 | F5:0.5 A5:0.5 C6:0.5 A5:0.5 G5:1 -:1 | E5:0.5 G5:0.5 A5:0.5 C6:0.5 E6:1 D6:1 | D6:0.5 B5:0.5 G5:0.5 B5:0.5 C6:2",
                bass: "C2:0.5 C3:0.5 C2:0.5 C3:0.5 C2:0.5 C3:0.5 C2:0.5 C3:0.5 | F2:0.5 F3:0.5 F2:0.5 F3:0.5 F2:0.5 F3:0.5 F2:0.5 F3:0.5 | C2:0.5 C3:0.5 C2:0.5 C3:0.5 C2:0.5 C3:0.5 C2:0.5 C3:0.5 | G2:0.5 G3:0.5 G2:0.5 G3:0.5 G2:0.5 G3:0.5 G2:0.5 G3:0.5 | C2:0.5 C3:0.5 C2:0.5 C3:0.5 C2:0.5 C3:0.5 C2:0.5 C3:0.5 | F2:0.5 F3:0.5 F2:0.5 F3:0.5 F2:0.5 F3:0.5 F2:0.5 F3:0.5 | A2:0.5 A3:0.5 A2:0.5 A3:0.5 A2:0.5 A3:0.5 A2:0.5 A3:0.5 | G2:0.5 G3:0.5 G2:0.5 G3:0.5 G2:0.5 G3:0.5 G2:0.5 G3:0.5",
                drumBar: "k.h.s.h.k.h.s.hh",
                bars: 8
            )
        case .retroRacer:
            // driving A minor
            return ChipTrack(
                bpm: 175,
                leadWaveform: .square,
                lead: "A4:0.5 A4:0.5 C5:0.5 E5:0.5 A5:1 G5:1 | E5:0.5 D5:0.5 C5:0.5 D5:0.5 E5:2 | F5:0.5 F5:0.5 A5:0.5 C6:0.5 B5:1 A5:1 | G5:0.5 A5:0.5 B5:0.5 G5:0.5 E5:2 | A5:0.5 G5:0.5 E5:0.5 A5:0.5 C6:1 B5:1 | A5:0.5 G5:0.5 E5:0.5 D5:0.5 E5:2 | F5:0.5 A5:0.5 C6:0.5 A5:0.5 G5:0.5 F5:0.5 E5:1 | D5:0.5 E5:0.5 F5:0.5 G#5:0.5 A5:2",
                bass: "A2:0.5 A3:0.5 A2:0.5 A3:0.5 A2:0.5 A3:0.5 A2:0.5 A3:0.5 | A2:0.5 A3:0.5 A2:0.5 A3:0.5 A2:0.5 A3:0.5 A2:0.5 A3:0.5 | F2:0.5 F3:0.5 F2:0.5 F3:0.5 F2:0.5 F3:0.5 F2:0.5 F3:0.5 | G2:0.5 G3:0.5 G2:0.5 G3:0.5 G2:0.5 G3:0.5 G2:0.5 G3:0.5 | A2:0.5 A3:0.5 A2:0.5 A3:0.5 A2:0.5 A3:0.5 A2:0.5 A3:0.5 | A2:0.5 A3:0.5 A2:0.5 A3:0.5 A2:0.5 A3:0.5 A2:0.5 A3:0.5 | F2:0.5 F3:0.5 F2:0.5 F3:0.5 F2:0.5 F3:0.5 F2:0.5 F3:0.5 | E2:0.5 E3:0.5 E2:0.5 E3:0.5 E2:0.5 E3:0.5 E2:0.5 E3:0.5",
                drumBar: "khhhskhhkhhhshhh",
                bars: 8
            )
        case .snake:
            // a sneaky E minor creep
            return ChipTrack(
                bpm: 126,
                leadWaveform: .pulse25,
                lead: "E4:0.5 -:0.5 G4:0.5 -:0.5 B4:0.5 A4:0.5 G4:1 | F#4:0.5 -:0.5 A4:0.5 -:0.5 B4:1 -:1 | E5:0.5 D5:0.5 B4:0.5 G4:0.5 C5:1 B4:1 | A4:0.5 B4:0.5 A4:0.5 F#4:0.5 D4:1 -:1 | E4:0.5 -:0.5 G4:0.5 -:0.5 B4:0.5 A4:0.5 G4:1 | F#4:0.5 -:0.5 A4:0.5 -:0.5 B4:1 E5:1 | G5:0.5 F#5:0.5 E5:0.5 D5:0.5 C5:1 E5:1 | D#5:0.5 F#5:0.5 B4:0.5 D#5:0.5 E5:2",
                bass: "E2:1 E2:1 E2:1 E2:1 | E2:1 E2:1 E2:1 E2:1 | C2:1 C2:1 C2:1 C2:1 | D2:1 D2:1 D2:1 D2:1 | E2:1 E2:1 E2:1 E2:1 | E2:1 E2:1 E2:1 E2:1 | C2:1 C2:1 C2:1 C2:1 | B1:1 B1:1 B1:1 B1:1",
                drumBar: "k...h...s...h...",
                bars: 8
            )
        case .fallingBlocks:
            // a D minor dance
            return ChipTrack(
                bpm: 140,
                leadWaveform: .pulse25,
                lead: "D5:1 A4:0.5 Bb4:0.5 C5:1 Bb4:0.5 A4:0.5 | G4:1 G4:0.5 Bb4:0.5 D5:1 C5:0.5 Bb4:0.5 | A4:1.5 Bb4:0.5 C5:1 E5:1 | D5:1 A4:1 D4:2 | F5:1 E5:0.5 D5:0.5 E5:1 D5:0.5 C5:0.5 | Bb4:1 D5:0.5 F5:0.5 G5:1 F5:0.5 E5:0.5 | E5:1 C#5:0.5 E5:0.5 A5:1 G5:1 | F5:0.5 E5:0.5 D5:0.5 C#5:0.5 D5:2",
                bass: "D2:1 A2:1 D3:1 A2:1 | G2:1 D3:1 G3:1 D3:1 | A2:1 E3:1 A3:1 E3:1 | D2:1 A2:1 D3:1 A2:1 | D2:1 A2:1 D3:1 A2:1 | G2:1 D3:1 G3:1 D3:1 | A2:1 E3:1 A3:1 E3:1 | D2:1 A2:1 D3:1 A2:1",
                drumBar: "k...h.h.s...h.h.",
                bars: 8
            )
        case .pixelInvaders:
            // the four-note bass march under a sparse lead
            return ChipTrack(
                bpm: 105,
                leadWaveform: .pulse12,
                lead: "-:2 B4:1 -:1 | -:2 C5:1 B4:1 | -:2 B4:1 -:1 | -:2 G4:1 F#4:1 | E5:1 -:1 D5:1 -:1 | C5:1 -:1 B4:1 A4:1 | G4:1 -:1 A4:1 B4:1 | C5:1 B4:1 A4:1 F#4:1",
                bass: "E2:1 D2:1 C2:1 B1:1 | E2:1 D2:1 C2:1 B1:1 | E2:1 D2:1 C2:1 B1:1 | E2:1 D2:1 C2:1 B1:1 | E2:1 D2:1 C2:1 B1:1 | E2:1 D2:1 C2:1 B1:1 | E2:1 D2:1 C2:1 B1:1 | E2:1 D2:1 C2:1 B1:1",
                drumBar: "................",
                bars: 8
            )
        case .mineSweep:
            // a calm F major
            return ChipTrack(
                bpm: 90,
                leadWaveform: .triangle,
                lead: "A4:1 C5:1 F5:1 E5:1 | D5:1 C5:1 A4:2 | Bb4:1 D5:1 G5:1 F5:1 | E5:1 G5:1 C5:2 | A4:1 C5:1 F5:1 A5:1 | G5:1 F5:1 D5:2 | Bb4:1 A4:1 G4:1 C5:1 | A4:1 G4:1 F4:2",
                bass: "F2:2 C3:2 | D2:2 A2:2 | A#1:2 F2:2 | C2:2 G2:2 | F2:2 C3:2 | D2:2 A2:2 | A#1:2 F2:2 | F2:2 C3:2",
                drumBar: "h.......h.......",
                bars: 8
            )
        case .mazeMuncher:
            // a bouncy G major
            return ChipTrack(
                bpm: 147,
                leadWaveform: .square,
                lead: "G5:0.5 B5:0.5 D6:0.5 B5:0.5 G5:0.5 B5:0.5 D6:1 | E5:0.5 G5:0.5 C6:0.5 G5:0.5 E5:0.5 G5:0.5 C6:1 | D5:0.5 F#5:0.5 A5:0.5 F#5:0.5 D5:0.5 F#5:0.5 A5:1 | B5:0.5 A5:0.5 G5:0.5 F#5:0.5 G5:2 | G5:0.5 G5:0.5 A5:0.5 B5:0.5 D6:1 B5:1 | C6:0.5 B5:0.5 A5:0.5 G5:0.5 E5:1 G5:1 | F#5:0.5 G5:0.5 A5:0.5 B5:0.5 C6:1 A5:1 | B5:0.5 D6:0.5 A5:0.5 F#5:0.5 G5:2",
                bass: "G2:0.5 G3:0.5 G2:0.5 G3:0.5 G2:0.5 G3:0.5 G2:0.5 G3:0.5 | C2:0.5 C3:0.5 C2:0.5 C3:0.5 C2:0.5 C3:0.5 C2:0.5 C3:0.5 | D2:0.5 D3:0.5 D2:0.5 D3:0.5 D2:0.5 D3:0.5 D2:0.5 D3:0.5 | G2:0.5 G3:0.5 G2:0.5 G3:0.5 G2:0.5 G3:0.5 G2:0.5 G3:0.5 | G2:0.5 G3:0.5 G2:0.5 G3:0.5 G2:0.5 G3:0.5 G2:0.5 G3:0.5 | C2:0.5 C3:0.5 C2:0.5 C3:0.5 C2:0.5 C3:0.5 C2:0.5 C3:0.5 | D2:0.5 D3:0.5 D2:0.5 D3:0.5 D2:0.5 D3:0.5 D2:0.5 D3:0.5 | G2:0.5 G3:0.5 G2:0.5 G3:0.5 G2:0.5 G3:0.5 G2:0.5 G3:0.5",
                drumBar: "k.h.s.h.k.h.s.h.",
                bars: 8
            )
        case .frogHop:
            // a playful D major
            return ChipTrack(
                bpm: 140,
                leadWaveform: .pulse25,
                lead: "D5:0.5 -:0.5 F#5:0.5 -:0.5 A5:0.5 F#5:0.5 D5:1 | E5:0.5 -:0.5 G5:0.5 -:0.5 B5:0.5 G5:0.5 E5:1 | F#5:0.5 A5:0.5 D6:0.5 A5:0.5 G5:0.5 F#5:0.5 E5:1 | D5:0.5 E5:0.5 F#5:0.5 A5:0.5 D5:2 | B5:0.5 A5:0.5 F#5:0.5 A5:0.5 B5:1 D6:1 | A5:0.5 G5:0.5 E5:0.5 G5:0.5 A5:1 C#6:1 | D6:0.5 C#6:0.5 B5:0.5 A5:0.5 G5:0.5 F#5:0.5 E5:1 | F#5:0.5 E5:0.5 C#5:0.5 E5:0.5 D5:2",
                bass: "D2:0.5 D3:0.5 D2:0.5 D3:0.5 D2:0.5 D3:0.5 D2:0.5 D3:0.5 | A2:0.5 A3:0.5 A2:0.5 A3:0.5 A2:0.5 A3:0.5 A2:0.5 A3:0.5 | D2:0.5 D3:0.5 D2:0.5 D3:0.5 D2:0.5 D3:0.5 D2:0.5 D3:0.5 | A2:0.5 A3:0.5 A2:0.5 A3:0.5 A2:0.5 A3:0.5 A2:0.5 A3:0.5 | B1:0.5 B2:0.5 B1:0.5 B2:0.5 B1:0.5 B2:0.5 B1:0.5 B2:0.5 | A2:0.5 A3:0.5 A2:0.5 A3:0.5 A2:0.5 A3:0.5 A2:0.5 A3:0.5 | G2:0.5 G3:0.5 G2:0.5 G3:0.5 G2:0.5 G3:0.5 G2:0.5 G3:0.5 | D2:0.5 D3:0.5 D2:0.5 D3:0.5 D2:0.5 D3:0.5 D2:0.5 D3:0.5",
                drumBar: "k.hhs.h.k.hhs.hh",
                bars: 8
            )
        case .lunarHinge:
            // slow E minor arpeggios in space
            return ChipTrack(
                bpm: 84,
                leadWaveform: .pulse12,
                lead: "E5:0.5 B5:0.5 E6:0.5 B5:0.5 G5:0.5 B5:0.5 E6:0.5 B5:0.5 | C5:0.5 G5:0.5 C6:0.5 G5:0.5 E5:0.5 G5:0.5 C6:0.5 G5:0.5 | D5:0.5 A5:0.5 D6:0.5 A5:0.5 F#5:0.5 A5:0.5 D6:0.5 A5:0.5 | B4:0.5 F#5:0.5 B5:0.5 F#5:0.5 D#5:0.5 F#5:0.5 B5:0.5 F#5:0.5 | E5:0.5 B5:0.5 E6:0.5 B5:0.5 G5:0.5 B5:0.5 E6:0.5 B5:0.5 | C5:0.5 G5:0.5 C6:0.5 G5:0.5 E5:0.5 G5:0.5 C6:0.5 G5:0.5 | D5:0.5 A5:0.5 D6:0.5 A5:0.5 F#5:0.5 A5:0.5 D6:0.5 A5:0.5 | E5:0.5 B5:0.5 E6:2 -:1",
                bass: "E2:4 | C2:4 | D2:4 | B1:4 | E2:4 | C2:4 | D2:4 | E2:4",
                drumBar: "................",
                bars: 8
            )
        case .paddleDuel:
            // a sporty G major volley
            return ChipTrack(
                bpm: 150,
                leadWaveform: .pulse25,
                lead: "G4:0.5 B4:0.5 D5:0.5 G5:0.5 D5:0.5 B4:0.5 G4:1 | A4:0.5 C5:0.5 E5:0.5 A5:0.5 E5:0.5 C5:0.5 A4:1 | B4:0.5 D5:0.5 F#5:0.5 B5:0.5 A5:0.5 F#5:0.5 D5:1 | C5:0.5 E5:0.5 G5:0.5 E5:0.5 D5:2 | G4:0.5 B4:0.5 D5:0.5 G5:0.5 D5:0.5 B4:0.5 G4:1 | E5:0.5 G5:0.5 B5:0.5 G5:0.5 A5:1 F#5:1 | G5:0.5 F#5:0.5 E5:0.5 D5:0.5 C5:0.5 B4:0.5 A4:1 | D5:0.5 F#5:0.5 A5:0.5 F#5:0.5 G5:2",
                bass: "G2:0.5 G3:0.5 G2:0.5 G3:0.5 G2:0.5 G3:0.5 G2:0.5 G3:0.5 | A2:0.5 A3:0.5 A2:0.5 A3:0.5 A2:0.5 A3:0.5 A2:0.5 A3:0.5 | B2:0.5 B3:0.5 B2:0.5 B3:0.5 B2:0.5 B3:0.5 B2:0.5 B3:0.5 | C3:0.5 C4:0.5 C3:0.5 C4:0.5 C3:0.5 C4:0.5 C3:0.5 C4:0.5 | G2:0.5 G3:0.5 G2:0.5 G3:0.5 G2:0.5 G3:0.5 G2:0.5 G3:0.5 | E2:0.5 E3:0.5 E2:0.5 E3:0.5 E2:0.5 E3:0.5 E2:0.5 E3:0.5 | C2:0.5 C3:0.5 C2:0.5 C3:0.5 C2:0.5 C3:0.5 C2:0.5 C3:0.5 | D2:0.5 D3:0.5 D2:0.5 D3:0.5 D2:0.5 D3:0.5 D2:0.5 D3:0.5",
                drumBar: "k.h.s.h.k.hks.h.",
                bars: 8
            )
        case .astroDrift:
            // a lonely A minor in deep space
            return ChipTrack(
                bpm: 105,
                leadWaveform: .pulse12,
                lead: "A4:1 E5:1 A5:1 G5:1 | F5:2 E5:1 C5:1 | D5:1 A4:1 D5:1 F5:1 | E5:3 -:1 | A4:1 E5:1 A5:1 B5:1 | C6:2 B5:1 G5:1 | A5:1 F5:1 D5:1 E5:1 | A4:3 -:1",
                bass: "A1:0.5 A2:0.5 A1:0.5 A2:0.5 A1:0.5 A2:0.5 A1:0.5 A2:0.5 | F1:0.5 F2:0.5 F1:0.5 F2:0.5 F1:0.5 F2:0.5 F1:0.5 F2:0.5 | D2:0.5 D3:0.5 D2:0.5 D3:0.5 D2:0.5 D3:0.5 D2:0.5 D3:0.5 | E2:0.5 E3:0.5 E2:0.5 E3:0.5 E2:0.5 E3:0.5 E2:0.5 E3:0.5 | A1:0.5 A2:0.5 A1:0.5 A2:0.5 A1:0.5 A2:0.5 A1:0.5 A2:0.5 | C2:0.5 C3:0.5 C2:0.5 C3:0.5 C2:0.5 C3:0.5 C2:0.5 C3:0.5 | F1:0.5 F2:0.5 F1:0.5 F2:0.5 F1:0.5 F2:0.5 F1:0.5 F2:0.5 | E2:0.5 E3:0.5 E2:0.5 E3:0.5 E2:0.5 E3:0.5 E2:0.5 E3:0.5",
                drumBar: "k...h.h.k.s.h...",
                bars: 8
            )
        case .towerStack:
            // a cheerful C major climb
            return ChipTrack(
                bpm: 135,
                leadWaveform: .square,
                lead: "C5:0.5 D5:0.5 E5:0.5 G5:0.5 E5:0.5 D5:0.5 C5:1 | D5:0.5 E5:0.5 F5:0.5 A5:0.5 G5:2 | E5:0.5 F5:0.5 G5:0.5 C6:0.5 B5:0.5 A5:0.5 G5:1 | F5:0.5 E5:0.5 D5:0.5 E5:0.5 C5:2 | C5:0.5 E5:0.5 G5:0.5 C6:0.5 E6:1 D6:1 | C6:0.5 A5:0.5 F5:0.5 A5:0.5 G5:2 | E5:0.5 G5:0.5 C6:0.5 G5:0.5 F5:0.5 D5:0.5 B4:1 | C5:1 G4:1 C5:2",
                bass: "C2:1 C3:1 C2:1 C3:1 | G2:1 G3:1 G2:1 G3:1 | C2:1 C3:1 C2:1 C3:1 | G2:1 G3:1 G2:1 G3:1 | C2:1 C3:1 C2:1 C3:1 | F2:1 F3:1 F2:1 F3:1 | G2:1 G3:1 G2:1 G3:1 | C2:1 C3:1 C2:1 C3:1",
                drumBar: "k.h.s.h.k.h.s.hh",
                bars: 8
            )
        }
    }

    /// A track's three looping patches, in `partsPerTrack` order.
    static func patches(for track: ChipTrack) -> [SynthPatchDefinition] {
        [
            SynthPatchDefinition(channel: .musicLead, priority: 0,
                                 notes: notes(fromScore: track.lead, bpm: track.bpm, waveform: track.leadWaveform, volume: 0.16),
                                 loops: true),
            SynthPatchDefinition(channel: .musicBass, priority: 0,
                                 notes: notes(fromScore: track.bass, bpm: track.bpm, waveform: .triangle, volume: 0.3),
                                 loops: true),
            SynthPatchDefinition(channel: .musicDrums, priority: 0,
                                 notes: drumNotes(fromBar: track.drumBar, bars: track.bars, bpm: track.bpm),
                                 loops: true)
        ]
    }

    // MARK: - Parsing

    /// Milliseconds in a sixteenth note.
    static func sixteenthMs(bpm: Int) -> Double {
        15_000 / Double(bpm)
    }

    /// Turns a score into notes. Unreadable tokens are skipped.
    static func notes(fromScore score: String, bpm: Int, waveform: Waveform, volume: Double) -> [SynthNote] {
        let sixteenth = sixteenthMs(bpm: bpm)
        var result: [SynthNote] = []
        for token in score.split(whereSeparator: { $0 == " " || $0 == "|" }) {
            let parts = token.split(separator: ":")
            guard parts.count == 2, let beats = Double(parts[1]) else { continue }
            let duration = (beats * 4).rounded() * sixteenth
            if parts[0] == "-" {
                result.append(.rest(duration))
            } else if let hz = frequency(of: parts[0]) {
                result.append(.tone(hz, duration, waveform, volume: volume))
            }
        }
        return result
    }

    /// Turns a one-bar drum pattern into notes for the whole track.
    static func drumNotes(fromBar pattern: String, bars: Int, bpm: Int) -> [SynthNote] {
        let sixteenth = sixteenthMs(bpm: bpm)
        let bar: [SynthNote] = pattern.map { step in
            switch step {
            case "k": return .tone(700, sixteenth, .noise, volume: 0.22, decays: true)
            case "s": return .tone(5_000, sixteenth, .noise, volume: 0.16, decays: true)
            case "h": return .tone(12_000, sixteenth, .noise, volume: 0.07, decays: true)
            default: return .rest(sixteenth)
            }
        }
        return Array((0..<bars).map { _ in bar }.joined())
    }

    /// The frequency of a note name such as "C#5" or "Bb3", nil if unreadable.
    static func frequency<S: StringProtocol>(of name: S) -> Double? {
        let semitones: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        var characters = Substring(name)
        guard let letter = characters.first, let base = semitones[letter] else { return nil }
        characters = characters.dropFirst()
        var accidental = 0
        if characters.first == "#" {
            accidental = 1
            characters = characters.dropFirst()
        } else if characters.first == "b" {
            accidental = -1
            characters = characters.dropFirst()
        }
        guard let octave = Int(characters) else { return nil }
        let midi = 12 * (octave + 1) + base + accidental
        return 440 * pow(2, Double(midi - 69) / 12)
    }

    /// A score's length in sixteenth notes, for checking parts line up.
    static func sixteenths(inScore score: String) -> Int {
        score.split(whereSeparator: { $0 == " " || $0 == "|" }).reduce(0) { total, token in
            let parts = token.split(separator: ":")
            guard parts.count == 2, let beats = Double(parts[1]) else { return total }
            return total + Int((beats * 4).rounded())
        }
    }
}
