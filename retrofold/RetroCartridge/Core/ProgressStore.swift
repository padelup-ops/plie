// ProgressStore.swift
// RetroCartridge
//
// The player's persistent progress: high scores per cartridge and mode, and
// the achievements earned. Values are held in stored properties, so every
// view showing a score refreshes as soon as a new record is set. Daily
// modes keep the day their record was set and start over the next day.

import Foundation
import Observation

@Observable
final class ProgressStore {

    // MARK: - Storage

    private let defaults: UserDefaults

    /// High scores by persistence key (`highScoreKey(for:mode:)`).
    private var highScores: [String: Int]

    /// For daily modes, the day (`DailySeed.dayKey`) each record was set.
    private var recordDays: [String: String]

    /// Today's day key. Injectable so tests can move through days.
    private let today: () -> String

    /// Identifiers of the achievements earned so far.
    private(set) var earnedAchievements: Set<String>

    private static let achievementsKey = "earnedAchievements"

    /// Loads the saved progress of every cartridge and mode.
    init(defaults: UserDefaults = .standard, today: @escaping () -> String = { DailySeed.dayKey() }) {
        self.defaults = defaults
        self.today = today

        var scores: [String: Int] = [:]
        var days: [String: String] = [:]
        for game in GameType.allCases {
            for mode in game.modes {
                let key = Self.highScoreKey(for: game, mode: mode)
                scores[key] = defaults.integer(forKey: key)
                if mode.isDaily {
                    days[key] = defaults.string(forKey: Self.dayKey(forScoreKey: key))
                }
            }
        }
        highScores = scores
        recordDays = days
        earnedAchievements = Set(defaults.stringArray(forKey: Self.achievementsKey) ?? [])
    }

    // MARK: - High Scores

    /// The persistence key of a high score. The standard mode keeps the key
    /// used before modes existed, so earlier scores carry over.
    static func highScoreKey(for game: GameType, mode: GameMode) -> String {
        mode.id == GameMode.standard.id
            ? "highScore_\(game.rawValue)"
            : "highScore_\(game.rawValue)_\(mode.id)"
    }

    /// Where the day of a daily record is stored.
    private static func dayKey(forScoreKey key: String) -> String {
        key + "_day"
    }

    /// The best score for a cartridge in a mode, 0 if never played. For a
    /// daily mode, only today's rounds count.
    func highScore(for game: GameType, mode: GameMode = .standard) -> Int {
        let key = Self.highScoreKey(for: game, mode: mode)
        if mode.isDaily && recordDays[key] != today() {
            return 0
        }
        return highScores[key] ?? 0
    }

    /// Saves `score` if it beats the current high score.
    /// - Returns: Whether it was a new high score.
    @discardableResult
    func recordScore(_ score: Int, for game: GameType, mode: GameMode = .standard) -> Bool {
        let key = Self.highScoreKey(for: game, mode: mode)
        guard score > highScore(for: game, mode: mode) else { return false }
        highScores[key] = score
        defaults.set(score, forKey: key)
        if mode.isDaily {
            let day = today()
            recordDays[key] = day
            defaults.set(day, forKey: Self.dayKey(forScoreKey: key))
        }
        return true
    }

    // MARK: - Achievements

    /// Whether the achievement with this identifier has been earned.
    func hasEarned(_ achievementID: String) -> Bool {
        earnedAchievements.contains(achievementID)
    }

    /// Marks an achievement as earned.
    /// - Returns: Whether it was newly earned.
    @discardableResult
    func earn(_ achievementID: String) -> Bool {
        guard !earnedAchievements.contains(achievementID) else { return false }
        earnedAchievements.insert(achievementID)
        defaults.set(earnedAchievements.sorted(), forKey: Self.achievementsKey)
        return true
    }
}
