// ProductIdentifiers.swift
// RetroCartridge
//
// StoreKit 2 product identifiers for In-App Purchases, plus the local
// catalog metadata the store screen falls back on when the App Store
// can't be reached.

import Foundation

/// Central registry of all IAP product identifiers.
enum ProductIdentifiers {
    /// RetroFold Pro — $2.99, the one purchase.
    /// Unlocks every paid item: the Maze Muncher, Frog Hop, Astro Drift and
    /// Lunar Hinge cartridges, every skin but Classic Grey, the Pocket,
    /// Arcade and Mellow sound packs, every screen mode but Color CRT, and
    /// screen tuning. It promises no future content: a later item opts in by
    /// naming it as its `requiredProductID`.
    static let pro = "com.padelup.retrofold.pro"

    /// All purchasable product IDs.
    static let allProductIDs: Set<String> = [pro]

    /// The order products are listed in the store.
    static let displayOrder: [String] = [pro]

    // MARK: - Fallback catalog

    /// Name shown when the StoreKit product couldn't be loaded, and spoken
    /// by VoiceOver.
    static func fallbackDisplayName(for productID: String) -> String {
        switch productID {
        case pro: return "RetroFold Pro"
        default: return productID
        }
    }

    /// Short uppercase name for lock labels, e.g. "RETROFOLD PRO".
    static func shortName(for productID: String) -> String {
        switch productID {
        case pro: return String(localized: "RETROFOLD PRO")
        default: return fallbackDisplayName(for: productID).uppercased()
        }
    }

    /// Price shown when the StoreKit product couldn't be loaded.
    static func fallbackDisplayPrice(for productID: String) -> String {
        switch productID {
        case pro: return "$2.99"
        default: return "—"
        }
    }

    // MARK: - Contents

    // Everything below is derived from each item's own `requiredProductID`,
    // so the store always lists exactly what a purchase opens.

    /// Whether buying a product unlocks an item that requires `required`.
    static func unlocks(_ productID: String, itemRequiring required: String?) -> Bool {
        required != nil && required == productID
    }

    /// The console skins a product unlocks.
    static func skins(unlockedBy productID: String) -> [ConsoleSkinType] {
        ConsoleSkinType.allCases.filter { unlocks(productID, itemRequiring: $0.requiredProductID) }
    }

    /// The cartridges a product unlocks.
    static func cartridges(unlockedBy productID: String) -> [GameType] {
        GameType.allCases.filter { unlocks(productID, itemRequiring: $0.info.requiredProductID) }
    }

    /// The sound packs a product unlocks.
    static func soundPacks(unlockedBy productID: String) -> [SoundPack] {
        SoundPack.allCases.filter { unlocks(productID, itemRequiring: $0.requiredProductID) }
    }

    /// The screen modes a product unlocks.
    static func screenModes(unlockedBy productID: String) -> [ScreenMode] {
        ScreenMode.allCases.filter { unlocks(productID, itemRequiring: $0.requiredProductID) }
    }

    /// Whether a product unlocks screen tuning.
    static func unlocksScreenTuning(_ productID: String) -> Bool {
        productID == pro
    }

    /// One sentence on what a product unlocks, written from its contents.
    static func summary(for productID: String) -> String {
        var parts: [String] = []
        let cartridgeCount = cartridges(unlockedBy: productID).count
        let skinCount = skins(unlockedBy: productID).count
        let packCount = soundPacks(unlockedBy: productID).count
        let modeCount = screenModes(unlockedBy: productID).count
        if cartridgeCount > 0 { parts.append(String(localized: "\(cartridgeCount) cartridges")) }
        if skinCount > 0 { parts.append(String(localized: "\(skinCount) skins")) }
        if packCount > 0 { parts.append(String(localized: "\(packCount) sound packs")) }
        if modeCount > 0 { parts.append(String(localized: "\(modeCount) screen modes with tuning")) }
        return parts.isEmpty ? "" : String(localized: "\(list(parts)).", comment: "A product summary sentence")
    }

    /// "a", "a and b", "a, b and c".
    private static func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        let and = String(localized: " and ", comment: "Joins the last two items of a list, with spaces")
        return items.dropLast().joined(separator: ", ") + and + items[items.count - 1]
    }
}
