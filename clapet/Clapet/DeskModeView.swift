import SwiftUI

// MARK: - Mode bureau
//
// L'iPhone Duo ouvert à moitié et posé sur la table, comme un petit portable : l'écran intérieur
// est en portrait, la charnière le coupe en deux à l'horizontale. La moitié du haut (debout)
// montre le chiffre du jour et la charnière ; la moitié posée, les détails et les raccourcis.

enum DeskRule {
    static let key = "deskMode"

    static var isOn: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }

    /// Écran intérieur (large) en portrait et charnière entre 60° et 150°.
    static func active(degrees: Double?, size: CGSize) -> Bool {
        if Demo.desk { return true }
        guard isOn, let d = degrees, (60...150).contains(d) else { return false }
        return size.width >= 560 && size.height > size.width
    }
}

struct DeskModeView: View {
    let look: DFLook
    @Environment(ClapetModel.self) private var model
    @Environment(\.openURL) private var openURL

    private let closedBelow = 12.0
    private var angle: Double { model.degrees ?? (Demo.desk ? 104 : 90) }
    private var numberWeight: Font.Weight { look == .classic ? .bold : .light }

    var body: some View {
        GeometryReader { safe in
            let insets = safe.safeAreaInsets
            GeometryReader { full in
                VStack(spacing: 0) {
                    upright
                        .padding(.top, insets.top)
                        .frame(width: full.size.width, height: full.size.height / 2)
                    flat
                        .padding(.bottom, insets.bottom)
                        .frame(width: full.size.width, height: full.size.height / 2)
                        .background(Color.dfCard.opacity(look == .minimal ? 0 : 0.55))
                }
            }
            .ignoresSafeArea()
        }
        .background(Color.dfBackground.ignoresSafeArea())
        .accessibilityElement(children: .contain)
    }

    // MARK: Moitié debout : le chiffre du jour

    private var upright: some View {
        let s = model.stats
        return VStack(spacing: 18) {
            Spacer(minLength: 0)
            Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .textCase(look == .minimal ? .uppercase : nil)
            HStack(alignment: .center, spacing: 36) {
                VStack(spacing: 2) {
                    Text("\(s.today)")
                        .font(.system(size: 150, weight: numberWeight))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.25), value: s.today)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("folds today")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 6) {
                    HingeArc(degrees: angle, closedBelow: closedBelow, line: 14)
                        .frame(width: 190, height: 104)
                        .overlay(alignment: .bottom) {
                            Text("\(Int(angle.rounded()))°")
                                .font(.system(size: 36, weight: .light))
                                .monospacedDigit()
                        }
                    Text("Desk mode")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.dfAccent)
                }
            }
            trend
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 18)
    }

    private var trend: some View {
        let s = model.stats
        let today = s.today
        let text: Text
        if let avg = s.recentAverage().map({ Int($0.rounded()) }) {
            let diff = today - avg
            if diff < 0 { text = Text("\(-diff) below your \(avg)/day average") }
            else if diff > 0 { text = Text("\(diff) above your \(avg)/day average") }
            else { text = Text("Right on your \(avg)/day average") }
        } else {
            text = Text("Your daily average shows up tomorrow")
        }
        return text
            .font(.headline)
            .foregroundStyle(Color.primary.opacity(0.8))
    }

    // MARK: Moitié posée : détails et raccourcis

    private var flat: some View {
        let s = model.stats
        return VStack(spacing: 16) {
            HStack(spacing: 12) {
                tile(Text("Time closed"), TimeFormat.narrow(s.closedTime()))
                tile(Text("Yesterday"), "\(s.yesterday())")
                tile(Text("Last 7 days"), "\(s.weekTotal)")
            }
            weekBars
            HStack(spacing: 12) {
                shortcut(Text("Weekly recap"), "chart.bar.doc.horizontal", "week")
                shortcut(Text("Your hours"), "clock.badge.checkmark", "hours")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func tile(_ title: Text, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            title
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.title2.weight(look == .classic ? .semibold : .regular))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.dfCard))
    }

    private var weekBars: some View {
        let week = model.stats.lastWeek()
        let top = max(1, week.map { $0.closes }.max() ?? 1)
        return HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(week.enumerated()), id: \.offset) { i, day in
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(i == week.count - 1 ? Color.dfAccent : Color.dfAccent.opacity(0.35))
                        .frame(height: max(4, 70 * CGFloat(day.closes) / CGFloat(top)))
                    Text(day.date, format: .dateTime.weekday(.narrow))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 92)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Last 7 days"))
    }

    private func shortcut(_ title: Text, _ symbol: String, _ host: String) -> some View {
        Button {
            if let url = URL(string: "clapet://\(host)") { openURL(url) }
        } label: {
            Label { title } icon: { Image(systemName: symbol) }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color.dfAccent.opacity(0.14)))
                .foregroundStyle(Color.dfAccent)
        }
        .buttonStyle(.plain)
    }
}
