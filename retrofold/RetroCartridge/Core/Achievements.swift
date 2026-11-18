// Achievements.swift
// RetroCartridge
//
// Five achievements per cartridge: score anything, reach its level goal,
// reach its score goal, finish a daily round and finish a round in every
// mode. They're checked every frame against the running game and stored by
// id in `ProgressStore`, which also keeps a hidden record of which modes
// each cartridge has finished.

import Foundation

// MARK: - Achievement

struct Achievement: Identifiable, Hashable, Sendable {

    /// What the player has to do.
    enum Goal: Hashable, Sendable {
        case score(Int)
        case level(Int)
        case finishDaily
        case finishEveryMode
    }

    let game: GameType
    let goal: Goal

    /// Name shown when earned, e.g. "HIGH SCORER". Looked up when read, so
    /// checking achievements every frame costs no string lookups.
    var title: String {
        switch goal {
        case .score(1): return String(localized: "OFF THE MARK")
        case .score: return String(localized: "HIGH SCORER")
        case .level(let level): return String(localized: "LEVEL \(level)")
        case .finishDaily: return String(localized: "DAILY PLAYER")
        case .finishEveryMode: return String(localized: "EXPLORER")
        }
    }

    /// What the player has to do, in words.
    var detail: String {
        switch goal {
        case .score(1): return String(localized: "Score your first points")
        case .score(let target): return String(localized: "Score \(target) in one round")
        case .level(let level): return String(localized: "Reach level \(level)")
        case .finishDaily: return String(localized: "Finish a daily round")
        case .finishEveryMode: return String(localized: "Finish a round in every mode")
        }
    }

    /// Stable id, used as the persistence key. Never change a shipped one.
    var id: String {
        switch goal {
        case .score(1): return "\(game.rawValue).first-points"
        case .score: return "\(game.rawValue).high-scorer"
        case .level: return "\(game.rawValue).level-goal"
        case .finishDaily: return "\(game.rawValue).daily"
        case .finishEveryMode: return "\(game.rawValue).explorer"
        }
    }

    /// Every achievement of a cartridge, in the order they're shown.
    static func all(for game: GameType) -> [Achievement] {
        let info = game.info
        return [
            Achievement(game: game, goal: .score(1)),
            Achievement(game: game, goal: .level(info.levelGoal)),
            Achievement(game: game, goal: .score(info.scoreGoal)),
            Achievement(game: game, goal: .finishDaily),
            Achievement(game: game, goal: .finishEveryMode)
        ]
    }
}

// MARK: - Tracker

enum AchievementTracker {

    /// The hidden record that a cartridge has finished a round in a mode.
    static func finishedModeID(game: GameType, mode: GameMode) -> String {
        "\(game.rawValue).finished.\(mode.id)"
    }

    /// Checks the running game and records what it has just earned.
    /// - Returns: The achievements earned by this call, to announce.
    @discardableResult
    static func check(_ game: any PixelGameProtocol, progress: ProgressStore) -> [Achievement] {
        let isRoundOver: Bool
        if case .gameOver = game.gameState { isRoundOver = true } else { isRoundOver = false }

        if isRoundOver {
            progress.earn(finishedModeID(game: game.gameType, mode: game.mode))
        }

        var earned: [Achievement] = []
        for achievement in Achievement.all(for: game.gameType) where !progress.hasEarned(achievement.id) {
            let isMet: Bool
            switch achievement.goal {
            case .score(let target):
                isMet = game.score >= target
            case .level(let target):
                isMet = game.level >= target
            case .finishDaily:
                isMet = isRoundOver && game.mode.isDaily
            case .finishEveryMode:
                isMet = game.gameType.modes.allSatisfy {
                    progress.hasEarned(finishedModeID(game: game.gameType, mode: $0))
                }
            }
            if isMet, progress.earn(achievement.id) {
                earned.append(achievement)
            }
        }
        return earned
    }

    /// How many of a cartridge's achievements are earned, out of how many.
    static func tally(for game: GameType, progress: ProgressStore) -> (earned: Int, total: Int) {
        let all = Achievement.all(for: game)
        return (all.filter { progress.hasEarned($0.id) }.count, all.count)
    }
}
