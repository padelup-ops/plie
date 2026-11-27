// Design.swift — Vicefold
//
// Le style de l'app : des cartes postales de Leonida. Titres d'affiche (Anton), fond d'eau de piscine le jour et de
// golfe la nuit, et des formes qui ont chacune un sens : le billet à encoches pour aller quelque part, le polaroïd
// pour un secret, l'affiche pour un personnage, l'égaliseur (comme la radio) pour la progression.

import SwiftUI
import UIKit

enum VFStyle {
    /// Les grands titres des écrans en Anton, comme une affiche.
    @MainActor static func apply() {
        let large = UIFont(name: "Anton-Regular", size: 38) ?? .systemFont(ofSize: 34, weight: .black)
        let small = UIFont(name: "Anton-Regular", size: 20) ?? .systemFont(ofSize: 17, weight: .bold)
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large)]
        bar.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: small)]
    }
}

/// Le fond des écrans (eau de piscine / golfe la nuit).
struct VFBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View { VF.backdrop(scheme == .dark).ignoresSafeArea() }
}

extension View {
    /// Une carte posée sur le fond : blanche le jour, bleu nuit le soir, coins doux, ombre légère.
    func vfCard(radius: CGFloat = 22, padding: CGFloat = 16) -> some View { modifier(VFCardStyle(radius: radius, padding: padding)) }
}

struct VFCardStyle: ViewModifier {
    var radius: CGFloat
    var padding: CGFloat
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VF.card(scheme == .dark), in: .rect(cornerRadius: radius, style: .continuous))
            .shadow(color: VF.ink.opacity(scheme == .dark ? 0 : 0.06), radius: 10, y: 4)
    }
}

/// Un billet : deux encoches sur les côtés, au niveau de la ligne pointillée.
struct TicketShape: Shape {
    var notch: CGFloat = 9
    /// La position de l'encoche, de 0 (haut) à 1 (bas).
    var at: CGFloat = 0.62
    func path(in r: CGRect) -> Path {
        let y = r.minY + r.height * at
        var p = Path(roundedRect: r, cornerRadius: 16, style: .continuous)
        p = p.subtracting(Path(ellipseIn: CGRect(x: r.minX - notch, y: y - notch, width: notch * 2, height: notch * 2)))
        p = p.subtracting(Path(ellipseIn: CGRect(x: r.maxX - notch, y: y - notch, width: notch * 2, height: notch * 2)))
        return p
    }
}

/// Un raccourci en forme de billet : l'icône, le nom, et un talon avec un mot.
struct TicketTile: View {
    var title: LocalizedStringKey
    var stub: LocalizedStringKey
    var icon: String
    var color: Color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.title2.weight(.semibold)).foregroundStyle(color)
                Text(title).font(VF.display(22, relativeTo: .title3)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 14).padding(.top, 14)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
            Line().stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])).foregroundStyle(color.opacity(0.45)).frame(height: 1).padding(.horizontal, 12)
            Text(stub).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 150)
        .background(VF.card(scheme == .dark), in: TicketShape(at: 0.66))
        .overlay(TicketShape(at: 0.66).stroke(color.opacity(0.35), lineWidth: 1))
    }

    private struct Line: Shape {
        func path(in r: CGRect) -> Path { var p = Path(); p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)); return p }
    }
}

/// La progression comme l'égaliseur d'un autoradio : une barre par catégorie, le total en grand.
struct ProgressEqualizer: View {
    var parts: Progress.Parts
    var compact = false

    var body: some View {
        let items: [(LocalizedStringKey, Double, Color)] = [("Missions", parts.missions, VF.flamingo), ("Places", parts.places, VF.palm),
                                                           ("Items", parts.collectibles, VF.sun), ("Challenges", parts.challenges, VF.sky)]
        HStack(alignment: .bottom, spacing: compact ? 10 : 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(parts.total, format: .percent.precision(.fractionLength(0)))
                    .font(VF.display(compact ? 44 : 58))
                    .monospacedDigit()
                    // Dans un demi-écran étroit (Duo ouvert), le total rétrécit au lieu de passer sur deux lignes.
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Text("of Leonida done").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                VStack(spacing: 6) {
                    GeometryReader { g in
                        ZStack(alignment: .bottom) {
                            Capsule().fill(it.2.opacity(0.16))
                            Capsule().fill(it.2.gradient).frame(height: max(6, g.size.height * min(1, it.1)))
                        }
                    }
                    .frame(width: compact ? 16 : 20, height: compact ? 64 : 84)
                    Text(it.1, format: .percent.precision(.fractionLength(0))).font(.caption2.weight(.bold)).monospacedDigit()
                    Text(it.0).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Le titre d'une partie d'écran : en Anton, avec une action à droite si besoin.
struct SectionTitle: View {
    var title: LocalizedStringKey
    var action: LocalizedStringKey?
    var tap: (() -> Void)?
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(VF.display(26, relativeTo: .title2))
            Spacer()
            if let action, let tap {
                Button(action, action: tap).font(.subheadline.weight(.semibold)).tint(VF.flamingo)
            }
        }
    }
}

/// Aller à un lieu sur la carte depuis n'importe quel écran.
@MainActor @Observable
final class AppRouter {
    static let shared = AppRouter()
    var mapPlace: VFPlace?
}

/// Le choix du jour : le même toute la journée, un autre demain (une raison d'ouvrir l'app chaque jour).
enum Daily {
    static func index(_ count: Int, salt: Int = 0) -> Int {
        guard count > 0 else { return 0 }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return abs((day &* 2_654_435_761 &+ salt &* 40_503) % count)
    }
}
