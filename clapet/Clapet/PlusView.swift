import SwiftUI

/// L'écran d'achat de Duo Folds+.
struct PlusView: View {
    @Environment(ClapetModel.self) private var model
    @Environment(ClapetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Pourquoi on l'ouvre (objectif atteint, fonction verrouillée…), affiché en haut.
    let reason: Text?

    init(reason: Text? = nil) {
        self.reason = reason
    }

    private let mint = Color(red: 0.43, green: 0.84, blue: 0.65)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.clapetInk, Color(red: 0.05, green: 0.16, blue: 0.14)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .bold))
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(Color.white.opacity(0.12)))
                        }
                        .accessibilityLabel(Text("Close"))
                    }
                    if let reason {
                        reason
                            .font(.system(.headline, design: .rounded, weight: .heavy))
                            .foregroundStyle(Color.clapetYellow)
                            .multilineTextAlignment(.center)
                    }
                    preview
                    VStack(spacing: 6) {
                        Text("Duo Folds+")
                            .font(.system(size: 38, weight: .black, design: .rounded))
                            .foregroundStyle(LinearGradient(colors: [mint, .clapetCyan], startPoint: .leading, endPoint: .trailing))
                        Text("Pay once, keep it forever. No subscription.")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        perk("rectangle.3.group.fill", Text("Every widget"), Text("The big Health-style widget, the medium one and the Lock Screen ones: your folds at a glance."))
                        perk("bell.badge.fill", Text("Limit alerts"), Text("A notification at 80 % and at 100 % of your daily limit."))
                        perk("calendar", Text("Your full history"), Text("30 days, 12 months, the calendar of days under your limit, your trends and records."))
                        perk("paintpalette.fill", Text("Widget colors"), Text("Five colors for your widgets."))
                        perk("square.and.arrow.up.fill", Text("Export"), Text("Your history as a spreadsheet (CSV)."))
                    }
                    .padding(18)
                    .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.06)))

                    if store.hasPlus {
                        Label { Text("Duo Folds+ is unlocked. Thank you!") } icon: { Image(systemName: "checkmark.seal.fill") }
                            .font(.system(.headline, design: .rounded, weight: .heavy))
                            .foregroundStyle(mint)
                            .padding(.vertical, 8)
                    } else {
                        Button {
                            Task { await store.buy() }
                        } label: {
                            HStack {
                                if store.isPurchasing { ProgressView().tint(.black) }
                                if let price = store.price {
                                    Text("Unlock for \(price)")
                                } else {
                                    Text("Unlock Duo Folds+")
                                }
                            }
                            .font(.system(.title3, design: .rounded, weight: .black))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(Capsule().fill(LinearGradient(colors: [mint, .clapetCyan], startPoint: .leading, endPoint: .trailing)))
                        }
                        .disabled(store.isPurchasing)
                        Button {
                            Task { await store.restore() }
                        } label: {
                            Text("Restore purchases")
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    if let message = store.message {
                        Text(message)
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(Color.clapetYellow)
                            .multilineTextAlignment(.center)
                    }
                    Text("One-time purchase, linked to your Apple Account. Counting, the daily limit, the week, the levels and the small widget stay free.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(.white)
        .task { await store.load() }
        .onChange(of: store.hasPlus) { _, has in
            if has {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
            }
        }
    }

    /// Un aperçu du grand widget, avec les vrais chiffres.
    private var preview: some View {
        let week = model.stats.lastWeek()
        let top = max(1, week.map(\.closes).max() ?? 1)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "iphone.gen3")
                Text("DUO FOLDS").tracking(0.8)
                Spacer()
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.5))
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(model.stats.totalCloses)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("all time")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(0..<week.count, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(i == week.count - 1 ? mint : Color.white.opacity(0.16))
                            .frame(width: 14, height: max(5, 54 * CGFloat(week[i].closes) / CGFloat(top)))
                    }
                }
            }
            HStack(spacing: 6) {
                Text("Level \(model.stats.level.number)")
                Text(model.stats.level.name).foregroundStyle(.white.opacity(0.5))
                Spacer()
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.16))
                    Capsule().fill(mint).frame(width: max(6, g.size.width * CGFloat(model.stats.level.progress(model.stats.totalCloses))))
                }
            }
            .frame(height: 6)
        }
        .padding(16)
        .frame(width: 290)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.13, green: 0.13, blue: 0.17), Color(red: 0.08, green: 0.08, blue: 0.11)], startPoint: .top, endPoint: .bottom)))
        .shadow(color: mint.opacity(0.25), radius: 24, y: 8)
        .rotationEffect(.degrees(-2))
        .accessibilityHidden(true)
    }

    private func perk(_ symbol: String, _ title: Text, _ detail: Text) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(mint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                title.font(.system(.headline, design: .rounded, weight: .heavy))
                detail
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Un petit cadenas « + » posé sur ce qui demande Duo Folds+.
struct PlusBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "lock.fill")
            Text("Plus")
        }
        .font(.system(size: 11, weight: .heavy, design: .rounded))
        .foregroundStyle(.black)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color(red: 0.43, green: 0.84, blue: 0.65)))
    }
}
