import SwiftUI

// MARK: - Mode bureau / livre
//
// L'iPhone Duo ouvert à moitié. Tenu comme un livre (écran intérieur en largeur, pli vertical) :
// le chiffre du jour sur la page de gauche, les détails sur celle de droite. Posé sur la table
// comme un petit portable (écran en hauteur, pli horizontal) : le chiffre debout en haut,
// les détails posés en bas.

enum DeskRule {
    static let key = "deskMode"

    static var isOn: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }

    /// Écran intérieur (assez grand) et charnière entre 60° et 150°.
    static func active(degrees: Double?, size: CGSize) -> Bool {
        if Demo.desk { return true }
        guard isOn, let d = degrees, (60...150).contains(d) else { return false }
        return max(size.width, size.height) >= 800
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
                if full.size.width > full.size.height {
                    // Comme un livre : deux pages de part et d'autre du pli.
                    HStack(spacing: 0) {
                        upright
                            .padding(.leading, insets.leading)
                            .padding(.vertical, max(insets.top, 12))
                            .frame(width: full.size.width / 2, height: full.size.height)
                        flat
                            .padding(.trailing, insets.trailing)
                            .padding(.vertical, max(insets.top, 12))
                            .frame(width: full.size.width / 2, height: full.size.height)
                            .background(Color.dfCard.opacity(look == .minimal ? 0 : 0.55))
                    }
                } else {
                    // Posé sur la table : le haut se tient debout, le bas est posé.
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
            }
            .ignoresSafeArea()
        }
        .background(DFBackdrop().ignoresSafeArea())
        .accessibilityElement(children: .contain)
    }

    // MARK: Moitié debout : le chiffre du jour

    private var upright: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .textCase(look == .minimal ? .uppercase : nil)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 36) { number; gauge }
                VStack(spacing: 14) { number; gauge }
            }
            trend
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 18)
    }

    private var number: some View {
        let s = model.stats
        return VStack(spacing: 2) {
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
    }

    private var gauge: some View {
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
        return ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    tile(Text("Time closed"), TimeFormat.narrow(s.closedTime()))
                    tile(Text("Yesterday"), "\(s.yesterday())")
                    tile(Text("Last 7 days"), "\(s.weekTotal)")
                }
                weekBars
                HStack(spacing: 12) {
                    tile(Text("Time open"), TimeFormat.narrow(s.openTime()))
                    if s.goalOn {
                        tile(Text("Streak"), "\(s.currentStreak()) 🔥")
                        tile(Text("Left today"), "\(max(0, s.left()))")
                    } else {
                        tile(Text("Record"), "\(s.best)")
                        tile(Text("Average"), s.recentAverage().map { "\(Int($0.rounded()))" } ?? "–")
                    }
                }
                todayByHour
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    shortcut(Text("Weekly recap"), "chart.bar.doc.horizontal", "week")
                    shortcut(Text("Monthly recap"), "calendar.badge.checkmark", "month")
                    shortcut(Text("Your hours"), "clock.badge.checkmark", "hours")
                    shortcut(Text("Leaderboards"), "trophy.fill", "boards")
                    shortcut(Text("Share my day"), "square.and.arrow.up", "share")
                    shortcut(Text("Settings"), "gearshape", "settings")
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Aujourd'hui, heure par heure (24 petites barres).
    private var todayByHour: some View {
        let hours = model.stats.hours()
        let top = max(1, hours.max() ?? 1)
        let now = Calendar.current.component(.hour, from: Date())
        return VStack(alignment: .leading, spacing: 8) {
            Text("Today, hour by hour")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<24, id: \.self) { h in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(h == now ? Color.dfAccent : Color.dfAccent.opacity(h < now ? 0.45 : 0.15))
                        .frame(height: max(3, 54 * CGFloat(h < hours.count ? hours[h] : 0) / CGFloat(top)))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 56, alignment: .bottom)
            HStack {
                ForEach([0, 6, 12, 18], id: \.self) { h in
                    Text(ContentView.hourLabel(h))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.dfCard))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Today, hour by hour"))
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
