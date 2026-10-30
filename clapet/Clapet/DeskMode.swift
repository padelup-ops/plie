import SwiftUI
import UIKit

// MARK: - Le mode bureau
//
// Posé plié en L (charnière à l'horizontale, entre 55° et 135°) avec Foldly à l'écran : la moitié du haut
// affiche l'heure et les chiffres du jour, en grand ; la moitié du bas reste sombre, avec un bouton pour sortir.
// L'écran reste allumé. On peut aussi l'ouvrir à la main depuis les menus.

@Observable
final class DeskCenter {
    static let shared = DeskCenter()
    var showing = false
    /// Fermé à la main : on ne le rouvre pas tout seul avant d'avoir quitté la position en L.
    var suppressed = false
    @ObservationIgnored var tabletopSince: Date?
}

enum DeskRule {
    private static let key = "desk.auto"

    /// Ouverture automatique en L : activée par défaut.
    static var autoOn: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Plié en L, posé : la charnière entre 55° et 135°, et l'écran plus large que haut (charnière à l'horizontale).
    static func isTabletop(degrees: Double?, size: CGSize) -> Bool {
        guard let d = degrees, size.width > 0 else { return false }
        return d > 55 && d < 135 && size.width > size.height
    }
}

struct DeskView: View {
    @Environment(ClapetModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var desk = DeskCenter.shared

    private let mint = Color(red: 0.36, green: 0.89, blue: 0.78)

    var body: some View {
        GeometryReader { g in
            let tabletop = DeskRule.isTabletop(degrees: model.degrees, size: g.size)
            ZStack {
                Color.black.ignoresSafeArea()
                if tabletop {
                    // La moitié du haut se lit debout ; celle du bas est posée sur la table.
                    VStack(spacing: 0) {
                        panel(compact: true)
                            .frame(height: g.size.height / 2)
                        bottom
                            .frame(height: g.size.height / 2)
                    }
                } else {
                    VStack(spacing: 28) {
                        Spacer(minLength: 0)
                        panel(compact: false)
                        Spacer(minLength: 0)
                        doneButton
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: model.degrees) { _, d in
            // Remis à plat ou refermé : on sort.
            if let d, d > 155 || d < 25 { close(manual: false) }
        }
    }

    // MARK: Les chiffres

    private func panel(compact: Bool) -> some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let now = context.date
            let s = model.stats
            VStack(spacing: compact ? 6 : 14) {
                Text(now, format: .dateTime.hour().minute())
                    .font(.system(size: compact ? 84 : 110, weight: .thin))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(.white)
                Text(now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(size: compact ? 15 : 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                HStack(alignment: .top, spacing: compact ? 34 : 40) {
                    figure("\(s.day(now).closes)", Text("folds today"), highlight: true)
                    figure(TimeFormat.short(s.openTime(now, now: now)), Text("open"))
                    figure(s.autoLast == nil && s.closedTime(now, now: now) == 0 ? "—" : TimeFormat.short(s.closedTime(now, now: now)),
                           Text("closed"))
                }
                .padding(.top, compact ? 4 : 10)
                Group {
                    if s.goalOn {
                        let left = s.left(now: now)
                        if left >= 0 { Text("\(left) left today") } else { Text("\(-left) over the limit") }
                    } else {
                        AverageText.status(today: s.day(now).closes, average: s.averageRef(now: now))
                    }
                }
                .font(.system(size: compact ? 14 : 16, weight: .medium))
                .foregroundStyle(mint)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func figure(_ value: String, _ label: Text, highlight: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 34, weight: highlight ? .regular : .light))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(highlight ? mint : .white)
            label
                .font(.system(size: 12, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.5))
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: La moitié du bas (posée sur la table)

    private var bottom: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            Text("Desk mode")
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(.white.opacity(0.35))
            doneButton
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.04))
    }

    private var doneButton: some View {
        Button { close(manual: true) } label: {
            Text("Done")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func close(manual: Bool) {
        if manual { desk.suppressed = true }
        desk.showing = false
        dismiss()
    }
}
