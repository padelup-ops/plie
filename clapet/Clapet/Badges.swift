import SwiftUI
import UIKit

// MARK: - Les badges du défi des plantes
//
// Calculés à partir des chiffres (rien à enregistrer pour les gagner), puis gardés pour toujours :
// un badge gagné ne se perd pas si l'objectif change ou si le vieil historique est effacé.

struct GardenBadge: Identifiable, Equatable {
    let id: String
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let target: Int
    let value: Int
    let kept: Bool

    var unlocked: Bool { kept || value >= target }
    var progress: Double { unlocked ? 1 : min(1, Double(value) / Double(max(1, target))) }

    static func == (a: GardenBadge, b: GardenBadge) -> Bool { a.id == b.id && a.unlocked == b.unlocked && a.value == b.value }
}

enum GardenBadges {
    private static let keptKey = "badges.unlocked"
    private static let seenKey = "badges.seen"

    static func all(_ s: ClapetStats, now: Date = Date()) -> [GardenBadge] {
        let kept = Set(UserDefaults.standard.stringArray(forKey: keptKey) ?? [])
        let plants = s.totalPlants
        let streak = s.bestDownGoalStreak(now: now)
        let resisted = s.totalResisted
        func badge(_ id: String, _ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey, _ target: Int, _ value: Int) -> GardenBadge {
            GardenBadge(id: id, symbol: symbol, title: title, detail: detail, target: target, value: value, kept: kept.contains(id))
        }
        return [
            badge("plant1", "leaf.fill", "First sprout", "Grow your first plant", 1, plants),
            badge("plant25", "camera.macro", "Little garden", "Grow 25 plants", 25, plants),
            badge("plant100", "tree.fill", "Gardener", "Grow 100 plants", 100, plants),
            badge("plant500", "tree.circle.fill", "Forest", "Grow 500 plants", 500, plants),
            badge("goal1", "checkmark.seal.fill", "Goal met", "Reach your phone-down goal", 1, streak),
            badge("goal3", "flame.fill", "3 days in a row", "Reach your goal 3 days in a row", 3, streak),
            badge("goal7", "calendar", "Green week", "Reach your goal 7 days in a row", 7, streak),
            badge("goal30", "crown.fill", "Green month", "Reach your goal 30 days in a row", 30, streak),
            badge("resist10", "hand.raised.fill", "Strong will", "Close your phone 10 times after the pause", 10, resisted)
        ]
    }

    /// Les badges gagnés depuis la dernière fois (et on les garde pour toujours).
    static func newlyUnlocked(_ s: ClapetStats) -> [GardenBadge] {
        let d = UserDefaults.standard
        let badges = all(s)
        let unlocked = badges.filter(\.unlocked)
        d.set(unlocked.map(\.id), forKey: keptKey)
        let seen = Set(d.stringArray(forKey: seenKey) ?? [])
        return unlocked.filter { !seen.contains($0.id) }
    }

    static func markSeen(_ badges: [GardenBadge]) {
        let d = UserDefaults.standard
        let seen = Set(d.stringArray(forKey: seenKey) ?? []).union(badges.map(\.id))
        d.set(Array(seen), forKey: seenKey)
    }
}

extension ClapetStats {
    /// L'objectif téléphone posé est atteint ce jour-là.
    func downGoalMet(_ date: Date, now: Date = Date()) -> Bool {
        let goal = Double(downGoalMinutes) * 60
        return goal > 0 && downTime(date, now: now) >= goal
    }

    /// La plus longue série de jours d'affilée avec l'objectif téléphone posé atteint.
    func bestDownGoalStreak(now: Date = Date()) -> Int {
        let cal = Calendar.current
        guard let first = days.keys.compactMap({ Self.date($0) }).min() else { return 0 }
        var best = 0
        var run = 0
        var day = cal.startOfDay(for: first)
        let end = cal.startOfDay(for: now)
        while day <= end {
            if downGoalMet(day, now: now) {
                run += 1
                best = max(best, run)
            } else {
                run = 0
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return best
    }

    /// Toutes les ouvertures évitées grâce à la pause.
    var totalResisted: Int { days.values.reduce(0) { $0 + $1.resisted } }
}

/// Une médaille : pleine et colorée une fois gagnée, grise avec sa progression sinon.
struct BadgeMedal: View {
    let badge: GardenBadge
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            if badge.unlocked {
                Circle().fill(Color.dfAccent)
                Circle().fill(LinearGradient(colors: [.white.opacity(0.28), .clear, .black.opacity(0.12)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
            } else {
                Circle().fill(Color.dfFill)
                Circle()
                    .trim(from: 0, to: badge.progress)
                    .stroke(Color.dfAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(1.5)
            }
            Image(systemName: badge.symbol)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(badge.unlocked ? Color.black.opacity(0.78) : Color.secondary)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Un badge dans la grille du jardin.
struct BadgeTile: View {
    let badge: GardenBadge

    var body: some View {
        VStack(spacing: 6) {
            BadgeMedal(badge: badge)
            Text(badge.title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .foregroundStyle(badge.unlocked ? Color.primary : Color.secondary)
            if !badge.unlocked {
                Text(verbatim: "\(min(badge.value, badge.target))/\(badge.target)")
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(badge.title))
        .accessibilityValue(badge.unlocked ? Text("Unlocked") : Text(badge.detail))
    }
}

/// Les badges à fêter d'un coup.
struct BadgeBatch: Identifiable {
    let id = UUID()
    let badges: [GardenBadge]
}

/// « Nouveau badge ! », à l'ouverture de l'app.
struct BadgeUnlockedView: View {
    let badges: [GardenBadge]
    @Environment(\.dismiss) private var dismiss
    @State private var pop = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let first = badges.first {
                    BadgeMedal(badge: first, size: 96)
                        .scaleEffect(pop ? 1 : 0.4)
                        .rotationEffect(.degrees(pop ? 0 : -20))
                        .padding(.top, 28)
                }
                Group {
                    if badges.count == 1 {
                        Text("New badge!")
                    } else {
                        Text("\(badges.count) new badges!")
                    }
                }
                .font(.title2.weight(.bold))
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(badges) { b in
                        HStack(spacing: 14) {
                            BadgeMedal(badge: b, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.title).font(.headline)
                                Text(b.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, 4)
                Button { dismiss() } label: {
                    Text("Great")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.dfAccent)
                .foregroundStyle(DFLook.current == .night ? Color.black : Color.white)
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(Color.dfBackground.ignoresSafeArea())
        .onAppear {
            GardenBadges.markSeen(badges)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { pop = true }
        }
    }
}
