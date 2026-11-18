// GameRNG.swift
// RetroCartridge
//
// Randomness for games. Every random choice a game makes (food, traffic,
// pieces, power-ups) goes through its `GameRNG`, so a daily round can deal
// the same game to everyone and tests can replay a game exactly.

import Foundation

// MARK: - Generator

/// A small, fast seedable generator (SplitMix64).
struct GameRNG: RandomNumberGenerator, Sendable {
    private var state: UInt64

    /// A generator that always produces the same sequence for `seed`.
    init(seed: UInt64) {
        state = seed
    }

    /// A generator with an unpredictable seed.
    init() {
        state = UInt64.random(in: .min ... .max)
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Daily seed

/// Seeds for daily rounds: the same for everyone on the same UTC day.
enum DailySeed {

    /// The UTC calendar day, e.g. "2026-09-29".
    static func dayKey(for date: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }

    /// A stable seed for a game on a day. Uses FNV-1a rather than
    /// `hashValue`, which changes from launch to launch.
    static func seed(for game: GameType, day: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in "\(game.rawValue)|\(day)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
