//
// RecordsView.swift
// RetroCartridge
//
// In-hierarchy overlay with the player's records: overall achievement
// progress, then for every cartridge its high score in each mode (the
// daily one counts today only) and its five achievements. Locked
// cartridges open the store on the product that unlocks them. Hosted by
// `LibraryOverlays` on both displays (never as a sheet).
//

import SwiftUI

struct RecordsView: View {
    @Environment(AppState.self) private var appState
    @Environment(StoreManager.self) private var storeManager
    @Environment(HapticManager.self) private var hapticManager
    @Environment(\.menuTheme) private var menuTheme

    /// Narrowest column of mode scores. It grows with the text, so at large
    /// sizes the modes stack instead of breaking "STANDARD" mid-word.
    @ScaledMetric(relativeTo: .body) private var modeColumnWidth: CGFloat = 120

    var body: some View {
        OverlayPanel(
            title: "RECORDS",
            subtitle: "HIGH SCORES AND ACHIEVEMENTS",
            onClose: close
        ) {
            VStack(spacing: 16) {
                overallProgress

                ForEach(GameType.allCases) { game in
                    cartridgeRow(game)
                }

                Button {
                    hapticManager.playHaptic(.buttonPress)
                    withAnimation(LibraryOverlays.animation) {
                        appState.showIntro()
                    }
                } label: {
                    RetroCapsuleLabel(title: String(localized: "HOW TO PLAY"), systemImage: "questionmark.circle.fill", tint: menuTheme.accent)
                }
                .buttonStyle(CartridgePressStyle())
                .padding(.top, 4)
            }
        }
    }

    private func close() {
        withAnimation(LibraryOverlays.animation) {
            appState.isRecordsVisible = false
        }
    }

    // MARK: - Overall

    private var overallProgress: some View {
        let tallies = GameType.allCases.map { AchievementTracker.tally(for: $0, progress: appState.progress) }
        let earned = tallies.reduce(0) { $0 + $1.earned }
        let total = tallies.reduce(0) { $0 + $1.total }

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ACHIEVEMENTS")
                    .retroFont(12, weight: .heavy)
                    .tracking(2.5)
                    .foregroundStyle(menuTheme.accent.opacity(0.85))
                Spacer(minLength: 8)
                Text("\(earned)/\(total)")
                    .retroFont(14, weight: .black)
                    .foregroundStyle(Self.gold)
            }
            ProgressView(value: Double(earned), total: Double(max(total, 1)))
                .tint(Self.gold)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(earned) of \(total) achievements earned")
    }

    private static let gold = Color(hex: "#FFD166")

    // MARK: - Cartridges

    @ViewBuilder
    private func cartridgeRow(_ game: GameType) -> some View {
        let isLocked = !storeManager.isUnlocked(game)

        if isLocked, let productID = game.info.requiredProductID {
            Button {
                hapticManager.playHaptic(.buttonPress)
                withAnimation(LibraryOverlays.animation) {
                    appState.openStore(highlighting: productID)
                }
            } label: {
                rowContent(game, lockedBy: productID)
            }
            .buttonStyle(CartridgePressStyle())
        } else {
            rowContent(game, lockedBy: nil)
        }
    }

    private func rowContent(_ game: GameType, lockedBy productID: String?) -> some View {
        let tally = AchievementTracker.tally(for: game, progress: appState.progress)

        return HStack(alignment: .top, spacing: 14) {
            CartridgeView(game: game, isLocked: productID != nil)
                .frame(width: 48)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(game.rawValue.uppercased())
                        .retroFont(14, weight: .heavy)
                        .tracking(1.2)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    if let productID {
                        Label(ProductIdentifiers.shortName(for: productID), systemImage: "lock.fill")
                            .retroFont(10, weight: .bold)
                            .foregroundStyle(RetroPalette.amber)
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                    } else {
                        Text("\(tally.earned)/\(tally.total) ★")
                            .retroFont(12, weight: .bold)
                            .foregroundStyle(tally.earned > 0 ? Self.gold : Color.white.opacity(0.35))
                    }
                }

                modeScores(game)

                achievementChips(game)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.07), lineWidth: 1))
        .opacity(productID == nil ? 1 : 0.6)
        .accessibilityElement(children: .combine)
    }

    /// Each mode's best score; the daily one is today's.
    private func modeScores(_ game: GameType) -> some View {
        let columns = [GridItem(.adaptive(minimum: modeColumnWidth), spacing: 8, alignment: .leading)]

        return LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(game.modes) { mode in
                let best = appState.progress.highScore(for: game, mode: mode)
                HStack(spacing: 6) {
                    Text((mode.isDaily ? String(localized: "TODAY") : mode.title).uppercased())
                        .foregroundStyle(.white.opacity(0.45))
                    Text(best > 0 ? "\(best)" : "—")
                        .foregroundStyle(best > 0 ? menuTheme.accent : Color.white.opacity(0.3))
                }
                .retroFont(11, weight: .bold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
        }
    }

    /// Earned achievements in gold, the rest dimmed, with what each asks for.
    private func achievementChips(_ game: GameType) -> some View {
        let columns = [GridItem(.adaptive(minimum: 150), spacing: 8, alignment: .leading)]

        return LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(Achievement.all(for: game)) { achievement in
                let isEarned = appState.progress.hasEarned(achievement.id)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(isEarned ? "★" : "☆") \(achievement.title)")
                        .retroFont(11, weight: .heavy)
                        .foregroundStyle(isEarned ? Self.gold : Color.white.opacity(0.5))
                    Text(achievement.detail)
                        .retroFont(10, weight: .medium)
                        .foregroundStyle(.white.opacity(isEarned ? 0.6 : 0.35))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityElement(children: .combine)
                .accessibilityValue(isEarned ? String(localized: "Earned") : String(localized: "Not earned"))
            }
        }
    }
}
