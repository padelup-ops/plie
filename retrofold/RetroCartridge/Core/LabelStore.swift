// LabelStore.swift
// RetroCartridge
//
// The player's own cartridge labels, drawn in the label designer. A custom
// label replaces the built-in artwork everywhere the cartridge appears (the
// shelf, the cover, records, the store), and the built-in one comes back
// when the custom label is removed. Labels are stored as rows of pixel
// characters (`PixelArt`), so they're tiny and easy to validate on load.

import Foundation
import Observation

@Observable
final class LabelStore {

    // MARK: - Storage

    private let defaults: UserDefaults

    /// The custom labels by cartridge. Cartridges without one use their
    /// built-in artwork.
    private(set) var customLabels: [GameType: PixelArt]

    private static let customLabelsKey = "customLabels"

    /// Loads the saved labels, dropping any that aren't a valid 16×16 grid.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let saved = (defaults.dictionary(forKey: Self.customLabelsKey) as? [String: [String]]) ?? [:]
        var labels: [GameType: PixelArt] = [:]
        for (rawValue, rows) in saved {
            guard let game = GameType(rawValue: rawValue) else { continue }
            let art = PixelArt(rows: rows)
            if art.isValid {
                labels[game] = art
            }
        }
        customLabels = labels
    }

    // MARK: - Labels

    /// The label a cartridge shows: the player's own, or its built-in artwork.
    func art(for game: GameType) -> PixelArt {
        customLabels[game] ?? PixelArt.label(for: game)
    }

    /// Whether the player has drawn this cartridge's label.
    func hasCustomLabel(for game: GameType) -> Bool {
        customLabels[game] != nil
    }

    /// Saves a cartridge's label. Drawing the built-in artwork back counts
    /// as removing the custom label; invalid art is ignored.
    func save(_ art: PixelArt, for game: GameType) {
        guard art.isValid else { return }
        customLabels[game] = art == PixelArt.label(for: game) ? nil : art
        persist()
    }

    /// Brings back a cartridge's built-in artwork.
    func removeCustomLabel(for game: GameType) {
        guard customLabels[game] != nil else { return }
        customLabels[game] = nil
        persist()
    }

    private func persist() {
        let rows = Dictionary(uniqueKeysWithValues: customLabels.map { ($0.key.rawValue, $0.value.rows) })
        defaults.set(rows, forKey: Self.customLabelsKey)
    }
}
