import SwiftUI

/// L'écran d'achat de Duo Folds+.
struct PlusView: View {
    @Environment(ClapetModel.self) private var model
    @Environment(ClapetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Pourquoi on l'ouvre (widget verrouillé, historique…), affiché en haut.
    let reason: Text?

    init(reason: Text? = nil) {
        self.reason = reason
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if let reason {
                        reason
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    preview
                    VStack(spacing: 6) {
                        Text("Duo Folds+")
                            .font(.largeTitle.weight(.bold))
                        Text("Pay once, keep it forever. No subscription.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        perk("rectangle.3.group", Text("Every widget"), Text("The big Health-style widget, the medium one and the Lock Screen ones: your folds at a glance."))
                        perk("bell.badge", Text("Limit alerts"), Text("A notification at 80 % and at 100 % of your daily limit."))
                        perk("calendar", Text("Your full history"), Text("30 days, 12 months, the calendar of days under your limit, your trends and records."))
                        perk("paintpalette", Text("Widget colors"), Text("Five colors for your widgets."))
                        perk("square.and.arrow.up", Text("Export"), Text("Your history as a spreadsheet (CSV)."))
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.dfCard))

                    if store.hasPlus {
                        Label { Text("Duo Folds+ is unlocked. Thank you!") } icon: { Image(systemName: "checkmark.seal.fill") }
                            .font(.headline)
                            .foregroundStyle(Color.dfAccent)
                            .padding(.vertical, 8)
                    } else {
                        Button {
                            Task { await store.buy() }
                        } label: {
                            HStack(spacing: 8) {
                                if store.isPurchasing { ProgressView().tint(.white) }
                                if let price = store.price {
                                    Text("Unlock for \(price)")
                                } else {
                                    Text("Unlock Duo Folds+")
                                }
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.dfAccent))
                        }
                        .disabled(store.isPurchasing)
                        Button {
                            Task { await store.restore() }
                        } label: {
                            Text("Restore purchases").font(.subheadline.weight(.medium))
                        }
                    }
                    if let message = store.message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Color.dfWarning)
                            .multilineTextAlignment(.center)
                    }
                    Text("One-time purchase, linked to your Apple Account. Counting, the daily limit, the week, the milestones and the small widget stay free.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Color.dfBackground)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Close") }
                }
            }
        }
        .tint(.dfAccent)
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
        let mint = Palette.mint
        let level = model.stats.level
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "iphone.gen3")
                Text("DUO FOLDS").tracking(0.6)
                Spacer()
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.5))
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(model.stats.totalCloses)")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(.white)
                    Text("all time")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(0..<week.count, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(i == week.count - 1 ? mint : Color.white.opacity(0.16))
                            .frame(width: 14, height: max(5, 54 * CGFloat(week[i].closes) / CGFloat(top)))
                    }
                }
            }
            if let next = level.next {
                Text("Next milestone: \(next)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.16))
                    Capsule().fill(mint).frame(width: max(6, g.size.width * CGFloat(level.progress(model.stats.totalCloses))))
                }
            }
            .frame(height: 6)
        }
        .padding(16)
        .frame(width: 290)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Palette.background))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .accessibilityHidden(true)
    }

    private func perk(_ symbol: String, _ title: Text, _ detail: Text) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.dfAccent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                title.font(.headline)
                detail
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Une petite étiquette « Plus » sur ce qui demande Duo Folds+.
struct PlusBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "lock.fill")
            Text("Plus")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Color.dfAccent)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.dfAccent.opacity(0.14)))
    }
}
