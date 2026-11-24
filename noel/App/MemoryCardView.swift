// MemoryCardView.swift — Allô Père Noël
//
// La carte souvenir : « Le Père Noël a appelé … ! », la date, le Père Noël dans un décor de Noël. Exportée en image
// (1080 × 1350) et partagée avec la feuille de partage d'iOS. Le prénom n'y figure que si le parent le choisit.

import SwiftUI

enum CardStyle: String, CaseIterable, Identifiable {
    case night, workshop, gold
    var id: String { rawValue }
    var isFree: Bool { self == .night }
    var label: LocalizedStringKey {
        switch self {
        case .night: return "Starry night"
        case .workshop: return "The workshop"
        case .gold: return "Golden snow"
        }
    }
}

struct MemoryCard: View {
    var style: CardStyle
    var name: String?
    var date: Date

    private var title: String {
        if let name, !name.isEmpty { return String(localized: "Santa called \(name)!") }
        return String(localized: "Santa called!")
    }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                Text("🎅").font(.system(size: 30)).padding(.top, 26)
                Text(title)
                    .font(.tale(30))
                    .foregroundStyle(style == .gold ? Noel.bordeaux : Noel.cream)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                    .padding(.horizontal, 26)
                    .padding(.top, 6)
                Text("A magical moment from the North Pole.")
                    .font(.story(16))
                    .foregroundStyle(style == .gold ? Noel.night.opacity(0.75) : Noel.goldLight)
                    .padding(.top, 6)
                Spacer(minLength: 0)
                SantaMedallion(size: 170, mood: .idle, still: 1.2)
                Spacer(minLength: 0)
                Text(date.formatted(date: .long, time: .omitted))
                    .font(.ui(14, .semibold))
                    .foregroundStyle(style == .gold ? Noel.night.opacity(0.7) : Noel.cream.opacity(0.85))
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Capsule().fill(style == .gold ? Color.white.opacity(0.6) : Noel.night.opacity(0.55)))
                    .padding(.bottom, 22)
            }
        }
        .frame(width: 360, height: 450)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Noel.goldGradient, lineWidth: 5).padding(9))
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .night:
            ZStack {
                NightScene(moon: true, trees: true, still: true)
                Snowfall(count: 70, still: true)
            }
        case .workshop:
            ZStack {
                LinearGradient(colors: [Color(red: 0.36, green: 0.14, blue: 0.10), Color(red: 0.20, green: 0.07, blue: 0.06)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color(red: 1, green: 0.62, blue: 0.25).opacity(0.5), .clear], center: .init(x: 0.5, y: 1.05), startRadius: 0, endRadius: 330)
                Canvas { ctx, s in
                    // une guirlande d'ampoules, figée
                    let colors: [Color] = [Noel.gold, Noel.red, Noel.goldLight, Color(red: 0.45, green: 0.85, blue: 0.55)]
                    for i in 0..<10 {
                        let u = (Double(i) + 0.5) / 10
                        let x = u * s.width
                        let y = 34 + 16 * sin(.pi * (u < 0.5 ? u * 2 : (u - 0.5) * 2))
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 12, y: y - 6, width: 24, height: 24)), with: .color(colors[i % 4].opacity(0.3)))
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 4, y: y + 2, width: 8, height: 11)), with: .color(colors[i % 4]))
                    }
                }
                Snowfall(count: 24, opacity: 0.4, still: true)
            }
        case .gold:
            ZStack {
                LinearGradient(colors: [Noel.cream, Color(red: 0.97, green: 0.88, blue: 0.68)], startPoint: .top, endPoint: .bottom)
                Canvas { ctx, s in
                    for i in 0..<46 {
                        let seed = Double(i) * 5.13
                        let x = fract(sin(seed) * 7919.3) * s.width
                        let y = fract(sin(seed * 1.9) * 3571.1) * s.height
                        let r = 3 + fract(sin(seed * 3.3) * 911.7) * 7
                        ctx.opacity = 0.35 + 0.5 * fract(seed)
                        ctx.fill(starPath(center: CGPoint(x: x, y: y), r: r), with: .color(Noel.gold))
                    }
                }
            }
        }
    }
}

struct MemoryCardView: View {
    @Environment(AppModel.self) private var model
    @Environment(MagicStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var scale
    @State private var style: CardStyle = .night
    @State private var showName = false
    @State private var image: Image?

    private var cardName: String? {
        showName ? model.profile.cleanNames.formatted(.list(type: .and)) : nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    MemoryCard(style: style, name: cardName, date: Date())
                        .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
                        .padding(.top, 8)

                    HStack(spacing: 10) {
                        ForEach(CardStyle.allCases) { s in
                            let locked = !s.isFree && !store.owned
                            Button {
                                if locked { model.sheet = .paywall } else { withAnimation(.snappy) { style = s } }
                            } label: {
                                VStack(spacing: 4) {
                                    Text(s.label).font(.ui(14, .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                                    if locked { PremiumTag() }
                                }
                                .foregroundStyle(style == s ? Noel.night : Noel.cream)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(style == s ? AnyShapeStyle(Noel.goldGradient) : AnyShapeStyle(Noel.night.opacity(0.7))))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Noel.cream.opacity(style == s ? 0 : 0.18), lineWidth: 1))
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    Toggle(isOn: $showName) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show the first name").font(.ui(16, .semibold))
                            Text("Off by default, to share without personal details.").font(.ui(13)).foregroundStyle(Noel.cream.opacity(0.6))
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Noel.night.opacity(0.7)))
                    .padding(.horizontal, 20)

                    if let image {
                        ShareLink(item: image, preview: SharePreview(Text("Santa called!"), image: image)) {
                            Label("Share the card", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(MagicButtonStyle())
                        .padding(.horizontal, 28)
                    }
                }
                .padding(.bottom, 30)
            }
            .background(Color(red: 0.05, green: 0.08, blue: 0.15).ignoresSafeArea())
            .navigationTitle(Text("A keepsake"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .task(id: "\(style.rawValue)-\(showName)") { render() }
    }

    @MainActor private func render() {
        let r = ImageRenderer(content: MemoryCard(style: style, name: cardName, date: Date()))
        r.scale = 3
        if let ui = r.uiImage { image = Image(uiImage: ui) }
    }
}
