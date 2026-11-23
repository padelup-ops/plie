// WidgetFaces.swift — Vicefold
//
// Le dessin des widgets, partagé entre l'extension (les vrais widgets) et l'app (leur aperçu dans le profil et les
// captures). Même allure que l'app : titres d'affiche en Anton, l'égaliseur des quatre parts du 100 %, l'eau de
// piscine le jour, le golfe la nuit.

import SwiftUI

enum VFWidgetSize { case small, medium, large, circular, rectangular, inline }

struct VFWidgetFace: View {
    var snap: VFSnapshot
    var size: VFWidgetSize
    var day: Int = VFWidgetFace.dayInLeonida()

    static func dayInLeonida(_ now: Date = Date()) -> Int {
        let cal = Calendar.current
        return (cal.dateComponents([.day], from: cal.startOfDay(for: VF.release), to: cal.startOfDay(for: now)).day ?? 0) + 1
    }

    var body: some View {
        switch size {
        case .circular:
            Gauge(value: snap.percent) { Text("VF") } currentValueLabel: { Text("\(Int(snap.percent * 100))") }
                .gaugeStyle(.accessoryCircularCapacity)
        case .rectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("\(Int(snap.percent * 100))% of Leonida").font(.headline)
                Text(snap.nextMission ?? String(localized: "All missions done")).font(.caption).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .inline:
            Text("\(Int(snap.percent * 100))% of Leonida")
        case .small:
            VStack(alignment: .leading, spacing: 0) {
                percent(38)
                Text("of Leonida done").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 6)
                bars(height: 40, labels: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .medium:
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    percent(40)
                    Text("of Leonida done").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer(minLength: 6)
                    bars(height: 44, labels: false)
                }
                .frame(width: 118, alignment: .leading)
                next
            }
        case .large:
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        percent(52)
                        Text("of Leonida done").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Day \(day) in Leonida").font(.system(size: 11, weight: .bold)).foregroundStyle(VF.flamingo)
                        .padding(.horizontal, 8).padding(.vertical, 4).background(VF.flamingo.opacity(0.14), in: .capsule)
                }
                bars(height: 70, labels: true)
                next.padding(12).background(.background.opacity(0.55), in: .rect(cornerRadius: 16))
            }
        }
    }

    private func percent(_ size: CGFloat) -> some View {
        Text("\(Int((snap.percent * 100).rounded()))%")
            .font(VF.display(size))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    /// Les quatre parts du 100 %, comme l'égaliseur de l'accueil.
    private func bars(height: CGFloat, labels: Bool) -> some View {
        let items: [(LocalizedStringKey, Double, Color, Int)] = [("Missions", snap.missions, VF.flamingo, 0), ("Places", snap.places, VF.palm, 1),
                                                                 ("Items", snap.collectibles, VF.sun, 2), ("Challenges", snap.challenges, VF.sky, 3)]
        return HStack(alignment: .bottom, spacing: labels ? 18 : 8) {
            ForEach(0..<items.count, id: \.self) { i in
                let it = items[i]
                VStack(spacing: 4) {
                    GeometryReader { g in
                        ZStack(alignment: .bottom) {
                            Capsule().fill(it.2.opacity(0.18))
                            Capsule().fill(it.2.gradient).frame(height: max(5, g.size.height * min(1, it.1)))
                        }
                    }
                    .frame(height: height)
                    if labels {
                        Text(count(it.3)).font(.system(size: 11, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        Text(it.0).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
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
        VStack(alignment: .leading, spacing: 3) {
            Text("Next mission").font(.system(size: 11, weight: .bold)).foregroundStyle(VF.flamingo)
            Text(snap.nextMission ?? String(localized: "All missions done"))
                .font(VF.display(size == .large ? 26 : 21)).lineLimit(2).minimumScaleFactor(0.7)
            if let c = snap.nextChapter { Text(c).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                if snap.hours > 0 { Label("\(Int(snap.hours)) h", systemImage: "clock") }
                if snap.eggs.count == 2, snap.eggs[1] > 0 { Label("\(snap.eggs[0])/\(snap.eggs[1])", systemImage: "oval.portrait") }
            }
            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Le fond des widgets : l'eau de piscine le jour, le golfe la nuit, avec le soleil couchant dans un coin.
struct VFWidgetBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VF.backdrop(scheme == .dark)
            Circle().fill(VF.gradient).frame(width: 140, height: 140).blur(radius: 50).opacity(scheme == .dark ? 0.35 : 0.28)
                .offset(x: 50, y: -60)
        }
    }
}
