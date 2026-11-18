//
// SkinPickerView.swift
// RetroCartridge
//
// In-hierarchy overlay listing every console skin as a miniature console.
// Tapping an unlocked skin equips it immediately; tapping a locked one opens
// the store on top. Hosted by `FullScreenLayout` (never as a sheet).
//

import SwiftUI

struct SkinPickerView: View {
    @Environment(AppState.self) private var appState
    @Environment(StoreManager.self) private var storeManager
    @Environment(HapticManager.self) private var hapticManager
    @Environment(AudioManager.self) private var audioManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.menuTheme) private var menuTheme

    private let columns = 2

    var body: some View {
        OverlayPanel(
            title: "CONSOLE SKINS",
            subtitle: "CHOOSE YOUR SHELL",
            onClose: close
        ) {
            VStack(spacing: 20) {
                Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                    ForEach(rows, id: \.self) { row in
                        GridRow {
                            ForEach(row) { skin in
                                skinCard(skin)
                            }
                        }
                    }
                }

                soundPacks

                if ConsoleSkinType.allCases.contains(where: { !storeManager.isUnlocked($0) }) {
                    upsell
                }
            }
        }
    }

    private var rows: [[ConsoleSkinType]] {
        let all = ConsoleSkinType.allCases
        return stride(from: 0, to: all.count, by: columns).map {
            Array(all[$0..<min($0 + columns, all.count)])
        }
    }

    // MARK: - Actions

    private func close() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            appState.isSkinSelectorVisible = false
        }
    }

    private func select(_ skin: ConsoleSkinType) {
        hapticManager.playHaptic(.buttonPress)

        guard storeManager.isUnlocked(skin) else {
            withAnimation(LibraryOverlays.animation) {
                appState.openStore(highlighting: skin.requiredProductID)
            }
            return
        }

        guard skin != appState.selectedSkin else { return }
        audioManager.playCartridgeClick()
        // The console and the menu colors cross-fade, unless Reduce Motion is on
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            appState.selectedSkin = skin
        }
    }

    // MARK: - Pieces

    private func skinCard(_ skin: ConsoleSkinType) -> some View {
        let isSelected = skin == storeManager.effectiveSkin(appState.selectedSkin)
        let isUnlocked = storeManager.isUnlocked(skin)

        return Button {
            select(skin)
        } label: {
            VStack(spacing: 12) {
                ConsoleSkinPreview(theme: SkinManager.theme(for: skin))
                    .frame(height: 150)
                    .saturation(isUnlocked ? 1 : 0.55)
                    .overlay {
                        if !isUnlocked {
                            OverlayLockBadge()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

                VStack(spacing: 5) {
                    Text(skin.rawValue.uppercased())
                        .retroFont(13, weight: .heavy)
                        .tracking(1.5)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    status(isSelected: isSelected, isUnlocked: isUnlocked, product: productName(for: skin))
                }
            }
            .overlayCard(isSelected: isSelected)
        }
        .buttonStyle(CartridgePressStyle())
        .accessibilityLabel(skin.rawValue)
        .accessibilityValue(isSelected ? String(localized: "Equipped") : (isUnlocked ? String(localized: "Unlocked") : String(localized: "Locked, part of \(ProductIdentifiers.fallbackDisplayName(for: skin.requiredProductID ?? ""))")))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The product that unlocks a skin, e.g. "RETROFOLD PRO".
    private func productName(for skin: ConsoleSkinType) -> String {
        skin.requiredProductID.map(ProductIdentifiers.shortName(for:)) ?? ""
    }

    @ViewBuilder
    private func status(isSelected: Bool, isUnlocked: Bool, product: String) -> some View {
        Group {
            if isSelected {
                Label("EQUIPPED", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(menuTheme.accent)
            } else if isUnlocked {
                Label("TAP TO EQUIP", systemImage: "hand.tap.fill")
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                Label(product, systemImage: "lock.fill")
                    .foregroundStyle(RetroPalette.amber)
            }
        }
        .retroFont(11, weight: .bold)
        .tracking(1)
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    // MARK: - Sound packs

    /// The sound pack chips: tap to hear and use one; locked packs open the store.
    private var soundPacks: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SOUND PACK")
                .retroFont(12, weight: .heavy)
                .tracking(2.5)
                .foregroundStyle(menuTheme.accent.opacity(0.85))

            HStack(spacing: 8) {
                ForEach(SoundPack.allCases) { pack in
                    soundPackChip(pack)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func soundPackChip(_ pack: SoundPack) -> some View {
        let isUnlocked = storeManager.isUnlocked(pack)
        let isSelected = storeManager.effectiveSoundPack(appState.soundPack) == pack

        return Button {
            hapticManager.playHaptic(.buttonPress)
            guard isUnlocked else {
                withAnimation(LibraryOverlays.animation) {
                    appState.openStore(highlighting: pack.requiredProductID)
                }
                return
            }
            appState.soundPack = pack
            // A sample in the new voice (RootView applies the pack right away)
            audioManager.soundPack = pack
            audioManager.playGameSound(.levelUp)
        } label: {
            RetroCapsuleLabel(
                title: pack.title.uppercased(),
                systemImage: isUnlocked ? (isSelected ? "checkmark" : "speaker.wave.2.fill") : "lock.fill",
                tint: isUnlocked ? menuTheme.accent : RetroPalette.amber,
                filled: isSelected
            )
        }
        .buttonStyle(CartridgePressStyle())
        .accessibilityLabel("\(pack.title) sound pack")
        .accessibilityValue(isSelected ? String(localized: "In use") : (isUnlocked ? String(localized: "Unlocked") : String(localized: "Locked")))
    }

    // MARK: - Upsell

    private var upsell: some View {
        Button {
            hapticManager.playHaptic(.buttonPress)
            withAnimation(LibraryOverlays.animation) {
                appState.openStore(highlighting: ProductIdentifiers.pro)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(RetroPalette.amber)
                Text("UNLOCK \(ProductIdentifiers.skins(unlockedBy: ProductIdentifiers.pro).count) SKINS WITH RETROFOLD PRO")
                    .retroFont(12, weight: .bold)
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                RetroCapsuleLabel(title: String(localized: "STORE"), systemImage: "bag.fill", tint: menuTheme.accent, filled: true)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(RetroPalette.amber.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(RetroPalette.amber.opacity(0.25), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(CartridgePressStyle())
    }
}
