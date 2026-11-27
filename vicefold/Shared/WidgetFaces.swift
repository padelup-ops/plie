// WidgetFaces.swift — Vicefold
//
// Le dessin des widgets, partagé entre l'extension (les vrais widgets) et l'app (leur aperçu dans le profil, la
// présentation et les captures). Même identité que l'app : la nuit de Leonida, le total en néon (Anton, dégradé
// du coucher de soleil), l'égaliseur des quatre parts du 100 %, des légendes d'instrument de bord.
// Les widgets sont toujours sombres, comme l'app ; en mode teinté, le total et les barres prennent la teinte.

import SwiftUI
import WidgetKit

enum VFWidgetSize { case small, medium, large, circular, rectangular, inline }

struct VFWidgetFace: View {
    var snap: VFSnapshot
    var size: VFWidgetSize
    var day: Int = VFWidgetFace.dayInLeonida()

    static func dayInLeonida(_ now: Date = Date()) -> Int {
        let cal = Calendar.current
        return (cal.dateComponents([.day], from: cal.startOfDay(for: VF.release), to: cal.startOfDay(for: now)).day ?? 0) + 1
    }

    private var pct: Int { Int((snap.percent * 100).rounded()) }

    var body: some View {
        switch size {
        case .circular:
            Gauge(value: snap.percent) { Text(verbatim: "VF") } currentValueLabel: { Text(verbatim: "\(pct)") }
                .gaugeStyle(.accessoryCircularCapacity)
        case .rectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("\(pct)% of Leonida").font(.headline)
                Text(snap.nextMission ?? String(localized: "All missions done")).font(.caption).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .inline:
            Text("\(pct)% of Leonida")
        case .small:
            VStack(alignment: .leading, spacing: 0) {
                percent(40)
                caption("of Leonida done")
                Spacer(minLength: 6)
                bars(height: 40, labels: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .medium:
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    percent(40)
                    caption("of Leonida done")
                    Spacer(minLength: 6)
                    bars(height: 44, labels: false)
                }
                .frame(width: 118, alignment: .leading)
                Rectangle().fill(VF.hairline).frame(width: 1)
                next
            }
        case .large:
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        percent(54)
                        caption("of Leonida done")
                    }
                    Spacer()
                    Text("Day \(day) in Leonida")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .textCase(.uppercase)
                        .foregroundStyle(VF.cyan)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(VF.cyan.opacity(0.12), in: .capsule)
                        .overlay(Capsule().stroke(VF.cyan.opacity(0.5), lineWidth: 1))
                }
                bars(height: 70, labels: true)
                next.padding(12)
                    .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VF.hairline, lineWidth: 1))
            }
        }
    }

    private func percent(_ size: CGFloat) -> some View {
        Text("\(pct)%")
            .font(VF.display(size))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(VF.gradient)
            .shadow(color: VF.flamingo.opacity(0.55), radius: 9)
            .widgetAccentable()
    }

    private func caption(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .textCase(.uppercase)
            .foregroundStyle(VF.textDim)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    /// Les quatre parts du 100 %, comme l'égaliseur de l'accueil.
    private func bars(height: CGFloat, labels: Bool) -> some View {
        let items: [(LocalizedStringKey, Double, Color, Int)] = [("Missions", snap.missions, VF.ringColors[0], 0), ("Places", snap.places, VF.ringColors[1], 1),
                                                                 ("Items", snap.collectibles, VF.ringColors[2], 2), ("Challenges", snap.challenges, VF.ringColors[3], 3)]
        return HStack(alignment: .bottom, spacing: labels ? 10 : 9) {
            ForEach(0..<items.count, id: \.self) { i in
                let it = items[i]
                VStack(spacing: 4) {
                    GeometryReader { g in
                        ZStack(alignment: .bottom) {
                            Capsule().fill(it.2.opacity(0.16))
                            Capsule().fill(LinearGradient(colors: [it.2, it.2.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                                .frame(height: max(5, g.size.height * min(1, it.1)))
                                .shadow(color: it.2.opacity(0.75), radius: 4)
                                .widgetAccentable()
                        }
                    }
                    .frame(width: labels ? 22 : 12, height: height)
                    if labels {
                        Text(count(it.3)).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(VF.text).lineLimit(1).minimumScaleFactor(0.6)
                        Text(it.0).font(.system(size: 9, weight: .semibold)).foregroundStyle(VF.textDim).lineLimit(1).minimumScaleFactor(0.5)
                    }
                }
                .frame(maxWidth: labels ? .infinity : nil)
            }
        }
    }

    private func count(_ i: Int) -> String {
        guard snap.counts.count >= i * 2 + 2 else { return "" }
        let done = snap.counts[i * 2], total = snap.counts[i * 2 + 1]
        return total > 0 ? "\(done)/\(total)" : ""
    }

    private var next: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Next mission")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .textCase(.uppercase)
                .foregroundStyle(VF.cyan)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(snap.nextMission ?? String(localized: "All missions done"))
                .font(VF.display(size == .large ? 26 : 21)).foregroundStyle(VF.text).lineLimit(2).minimumScaleFactor(0.7)
            if let c = snap.nextChapter { Text(c).font(.caption2).foregroundStyle(VF.textDim).lineLimit(1) }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                if snap.hours > 0 { Label("\(Int(snap.hours)) h", systemImage: "clock") }
                if snap.eggs.count == 2, snap.eggs[1] > 0 { Label("\(snap.eggs[0])/\(snap.eggs[1])", systemImage: "oval.portrait") }
            }
            .font(.caption2.weight(.semibold)).foregroundStyle(VF.textDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Le compte des jours depuis la sortie (ou avant) : le nombre en néon, la légende dessous.
struct VFDaysFace: View {
    /// Jours écoulés depuis la sortie (négatif : jours restants).
    var days: Int

    var body: some View {
        VStack(spacing: 2) {
            Text(verbatim: days < 0 ? "\(-days)" : "\(days + 1)")
                .font(VF.display(58)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.5)
                .foregroundStyle(VF.gradient)
                .shadow(color: VF.flamingo.opacity(0.55), radius: 10)
                .widgetAccentable()
            Text(days < 0 ? String(localized: "days to go") : String(localized: "days in Leonida"))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .textCase(.uppercase)
                .foregroundStyle(VF.textDim)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    static func days(_ now: Date = Date()) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: VF.release), to: cal.startOfDay(for: now)).day ?? 0
    }
}

/// Le fond des widgets : la nuit de Leonida, une lueur de coucher de soleil en bas et un reflet violet en haut.
struct VFWidgetBackground: View {
    var body: some View {
        ZStack {
            VF.abyss
            RadialGradient(colors: [VF.violet.opacity(0.42), VF.violet.opacity(0)], center: .topTrailing, startRadius: 0, endRadius: 190)
            RadialGradient(colors: [VF.flamingo.opacity(0.30), VF.flamingo.opacity(0)], center: .bottomLeading, startRadius: 0, endRadius: 170)
            LinearGradient(colors: [.white.opacity(0.05), .clear], startPoint: .top, endPoint: .center)
        }
    }
}
