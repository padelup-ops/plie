import SwiftUI

// MARK: - Les « photos » du téléphone, dessinées
//
// Un style illustré, cohérent d'une histoire à l'autre : des aplats de couleur, une lumière douce.

struct ArtView: View {
    let art: Illustration

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                switch art {
                case .pixelSleeping: sleepingCat(w, h)
                case .polaroidPixel: polaroid(w, h)
                case .birthday: birthday(w, h)
                case .loireSunset: sunset(w, h)
                case .studio: studio(w, h)
                case .coffee: coffee(w, h)
                case .trainWindow: train(w, h)
                case .flowers: flowers(w, h)
                case .catOnDesk: catDesk(w, h)
                case .streetStudio: street(w, h, sky: [Color(red: 0.62, green: 0.75, blue: 0.9), Color(red: 0.85, green: 0.88, blue: 0.92)],
                                           walls: [Color(red: 0.9, green: 0.85, blue: 0.75), Color(red: 0.75, green: 0.55, blue: 0.45), Color(red: 0.85, green: 0.8, blue: 0.7)], sign: "LUMEN")
                case .streetHome: street(w, h, sky: [Color(red: 0.95, green: 0.7, blue: 0.5), Color(red: 0.98, green: 0.88, blue: 0.7)],
                                         walls: [Color(red: 0.95, green: 0.92, blue: 0.85), Color(red: 0.88, green: 0.86, blue: 0.8), Color(red: 0.7, green: 0.62, blue: 0.55)], sign: nil)
                case .parkGate: park(w, h)
                case .station: station(w, h)
                }
            }
            .frame(width: w, height: h)
            .clipped()
        }
    }

    // MARK: Le chat

    private func cat(color: Color, size: CGFloat) -> some View {
        ZStack {
            Ellipse().fill(color).frame(width: size, height: size * 0.62).offset(y: size * 0.12)
            Circle().fill(color).frame(width: size * 0.5).offset(x: -size * 0.32, y: -size * 0.02)
            Triangle().fill(color).frame(width: size * 0.16, height: size * 0.18).offset(x: -size * 0.45, y: -size * 0.24)
            Triangle().fill(color).frame(width: size * 0.16, height: size * 0.18).offset(x: -size * 0.2, y: -size * 0.24)
            // yeux fermés
            Capsule().fill(Color.black.opacity(0.55)).frame(width: size * 0.08, height: size * 0.015).offset(x: -size * 0.4, y: -size * 0.02)
            Capsule().fill(Color.black.opacity(0.55)).frame(width: size * 0.08, height: size * 0.015).offset(x: -size * 0.24, y: -size * 0.02)
            Circle().fill(Color(red: 0.95, green: 0.55, blue: 0.6)).frame(width: size * 0.035).offset(x: -size * 0.32, y: size * 0.05)
            // queue
            Capsule().fill(color).frame(width: size * 0.5, height: size * 0.1).rotationEffect(.degrees(-20)).offset(x: size * 0.42, y: size * 0.3)
            // rayures
            ForEach(0..<3) { i in
                Capsule().fill(Color.black.opacity(0.12)).frame(width: size * 0.06, height: size * 0.3)
                    .offset(x: CGFloat(i) * size * 0.14, y: size * 0.05)
            }
        }
    }

    private func sleepingCat(_ w: CGFloat, _ h: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.98, green: 0.86, blue: 0.7), Color(red: 0.93, green: 0.62, blue: 0.45)], startPoint: .top, endPoint: .bottom)
            // couverture à carreaux
            ForEach(0..<8) { i in
                Rectangle().fill(Color(red: 0.75, green: 0.3, blue: 0.3).opacity(0.18)).frame(width: w, height: h * 0.04).offset(y: h * (0.1 + CGFloat(i) * 0.11) - h / 2)
            }
            cat(color: Color(red: 0.93, green: 0.6, blue: 0.3), size: min(w, h) * 0.7).offset(y: h * 0.08)
            Text("z z")
                .font(.system(size: min(w, h) * 0.08, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .offset(x: -w * 0.25, y: -h * 0.22)
        }
    }

    private func polaroid(_ w: CGFloat, _ h: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.2, green: 0.17, blue: 0.3), Color(red: 0.45, green: 0.27, blue: 0.35)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: h * 0.02) {
                sleepingCat(w * 0.62, w * 0.62)
                    .frame(width: w * 0.62, height: w * 0.62)
                    .clipped()
                Text("Pixel ♡ 14/03")
                    .font(.custom("Noteworthy-Bold", size: w * 0.07))
                    .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.35))
                    .padding(.bottom, h * 0.01)
            }
            .padding(w * 0.04)
            .background(Color(red: 0.98, green: 0.97, blue: 0.93))
            .rotationEffect(.degrees(-4))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 8)
            .offset(y: h * 0.05)
        }
    }

    // MARK: L'anniversaire

    private func person(_ shirt: Color, hair: Color, size: CGFloat) -> some View {
        VStack(spacing: -size * 0.04) {
            ZStack {
                Circle().fill(Color(red: 0.94, green: 0.78, blue: 0.65)).frame(width: size * 0.42)
                Capsule().fill(hair).frame(width: size * 0.46, height: size * 0.2).offset(y: -size * 0.14)
            }
            RoundedRectangle(cornerRadius: size * 0.18).fill(shirt).frame(width: size * 0.7, height: size * 0.8)
        }
    }

    private func birthday(_ w: CGFloat, _ h: CGFloat) -> some View {
        let s = min(w / 4.6, h / 1.9)
        return ZStack {
            LinearGradient(colors: [Color(red: 0.28, green: 0.22, blue: 0.45), Color(red: 0.55, green: 0.3, blue: 0.5)], startPoint: .top, endPoint: .bottom)
            // guirlande
            ForEach(0..<9) { i in
                Circle().fill([Color.yellow, .pink, .orange][i % 3].opacity(0.9)).frame(width: s * 0.12)
                    .offset(x: (CGFloat(i) - 4) * w * 0.1, y: -h * 0.38 + abs(CGFloat(i) - 4) * h * 0.012)
            }
            // ballons
            ForEach(0..<3) { i in
                Ellipse().fill([Color.pink, .cyan, .yellow][i].opacity(0.85)).frame(width: s * 0.4, height: s * 0.5)
                    .offset(x: w * (0.32 + CGFloat(i) * 0.06), y: -h * (0.2 + CGFloat(i % 2) * 0.08))
            }
            HStack(alignment: .bottom, spacing: s * 0.1) {
                person(Color(red: 0.3, green: 0.75, blue: 0.7), hair: .black, size: s)          // Samir
                person(Color(red: 0.95, green: 0.45, blue: 0.55), hair: Color(red: 0.35, green: 0.2, blue: 0.1), size: s * 0.92) // Inès
                person(Color(red: 0.4, green: 0.42, blue: 0.5), hair: Color(red: 0.6, green: 0.45, blue: 0.25), size: s * 1.05) // Hugo
                person(Color(red: 1.0, green: 0.78, blue: 0.3), hair: Color(red: 0.55, green: 0.25, blue: 0.15), size: s * 0.9) // Nina
            }
            .offset(y: h * 0.12)
            // gâteau
            RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.98, green: 0.9, blue: 0.85)).frame(width: s * 0.9, height: s * 0.3).offset(y: h * 0.42)
        }
    }

    // MARK: Les autres photos

    private func sunset(_ w: CGFloat, _ h: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.35, green: 0.25, blue: 0.55), Color(red: 0.98, green: 0.55, blue: 0.4), Color(red: 1.0, green: 0.8, blue: 0.5)], startPoint: .top, endPoint: .center)
            Circle().fill(Color(red: 1.0, green: 0.85, blue: 0.55)).frame(width: w * 0.25).offset(y: h * 0.02)
            Rectangle().fill(LinearGradient(colors: [Color(red: 0.45, green: 0.35, blue: 0.55), Color(red: 0.2, green: 0.2, blue: 0.4)], startPoint: .top, endPoint: .bottom))
                .frame(height: h * 0.45).offset(y: h * 0.28)
            // grues jaunes
            ForEach(0..<2) { i in
                Path { p in
                    let x = w * (0.18 + CGFloat(i) * 0.55), y = h * 0.55
                    p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x, y: y - h * 0.32))
                    p.addLine(to: CGPoint(x: x + w * 0.2, y: y - h * 0.32))
                }
                .stroke(Color(red: 0.95, green: 0.78, blue: 0.2), lineWidth: 4)
                .frame(width: w, height: h)
                .offset(x: -w / 2 + w / 2, y: 0)
            }
            ForEach(0..<6) { i in
                Capsule().fill(Color.white.opacity(0.35)).frame(width: w * 0.2, height: 2).offset(x: CGFloat(i % 3 - 1) * w * 0.2, y: h * (0.15 + CGFloat(i) * 0.05))
            }
        }
    }

    private func studio(_ w: CGFloat, _ h: CGFloat) -> some View {
        ZStack {
            Color(red: 0.9, green: 0.9, blue: 0.92)
            Ellipse().fill(Color.white).frame(width: w * 0.9, height: h * 0.5).offset(y: h * 0.3)
            // softbox
            RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.2)).frame(width: w * 0.25, height: h * 0.3).offset(x: -w * 0.3, y: -h * 0.15)
            RoundedRectangle(cornerRadius: 6).fill(Color.white).frame(width: w * 0.2, height: h * 0.25).offset(x: -w * 0.3, y: -h * 0.15)
            Rectangle().fill(Color(white: 0.25)).frame(width: 3, height: h * 0.45).offset(x: -w * 0.3, y: h * 0.2)
            // appareil photo
            RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.15)).frame(width: w * 0.3, height: h * 0.18).offset(x: w * 0.15, y: h * 0.05)
            Circle().fill(Color(white: 0.3)).frame(width: w * 0.13).offset(x: w * 0.15, y: h * 0.05)
            Circle().fill(Color(red: 0.2, green: 0.3, blue: 0.5)).frame(width: w * 0.07).offset(x: w * 0.15, y: h * 0.05)
        }
    }

    private func coffee(_ w: CGFloat, _ h: CGFloat) -> some View {
        ZStack {
            Color(red: 0.55, green: 0.38, blue: 0.28)
            Circle().fill(Color.white).frame(width: min(w, h) * 0.6)
            Circle().fill(Color(red: 0.42, green: 0.25, blue: 0.15)).frame(width: min(w, h) * 0.46)
            Image(systemName: "heart.fill").font(.system(size: min(w, h) * 0.16)).foregroundStyle(Color(red: 0.95, green: 0.88, blue: 0.75))
            RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.96, green: 0.93, blue: 0.85)).frame(width: w * 0.16, height: h * 0.05).offset(x: w * 0.34, y: h * 0.3)
        }
    }

    private func train(_ w: CGFloat, _ h: CGFloat) -> some View {
        ZStack {
            Color(red: 0.25, green: 0.27, blue: 0.32)
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(colors: [Color(red: 0.6, green: 0.75, blue: 0.9), Color(red: 0.55, green: 0.75, blue: 0.5)], startPoint: .top, endPoint: .bottom))
                .frame(width: w * 0.78, height: h * 0.6)
            ForEach(0..<5) { i in
                Rectangle().fill(Color(red: 0.3, green: 0.5, blue: 0.3)).frame(width: w * 0.02, height: h * 0.15)
                    .offset(x: (CGFloat(i) - 2) * w * 0.14, y: h * 0.1)
            }
        }
    }

    private func flowers(_ w: CGFloat, _ h: CGFloat) -> some View {
        ZStack {
            Color(red: 0.55, green: 0.75, blue: 0.5)
            ForEach(0..<7) { i in
                let x = CGFloat((i * 37) % 100) / 100 - 0.5, y = CGFloat((i * 53) % 100) / 100 - 0.5
                ZStack {
                    ForEach(0..<5) { k in
                        Ellipse().fill([Color.pink, .white, .yellow, .orange][i % 4]).frame(width: w * 0.06, height: w * 0.12)
                            .offset(y: -w * 0.05).rotationEffect(.degrees(Double(k) * 72))
                    }
                    Circle().fill(Color.yellow).frame(width: w * 0.04)
                }
                .offset(x: x * w * 0.8, y: y * h * 0.8)
            }
        }
    }

    private func catDesk(_ w: CGFloat, _ h: CGFloat) -> some View {
        ZStack {
            Color(red: 0.85, green: 0.8, blue: 0.75)
            RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.2)).frame(width: w * 0.6, height: h * 0.4).offset(y: -h * 0.12)
            RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.3, green: 0.45, blue: 0.7)).frame(width: w * 0.55, height: h * 0.34).offset(y: -h * 0.12)
            cat(color: Color(red: 0.93, green: 0.6, blue: 0.3), size: w * 0.45).offset(x: w * 0.05, y: h * 0.25)
        }
    }
    // MARK: Les photos de l'album masqué (la voiture est ajoutée par-dessus)

    private func street(_ w: CGFloat, _ h: CGFloat, sky: [Color], walls: [Color], sign: String?) -> some View {
        ZStack {
            LinearGradient(colors: sky, startPoint: .top, endPoint: .bottom)
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(0..<3) { i in
                    ZStack {
                        Rectangle().fill(walls[i])
                        VStack(spacing: h * 0.05) {
                            ForEach(0..<3) { _ in
                                HStack(spacing: w * 0.05) {
                                    ForEach(0..<2) { _ in
                                        RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.35, green: 0.45, blue: 0.6).opacity(0.75))
                                            .frame(width: w * 0.08, height: h * 0.09)
                                    }
                                }
                            }
                        }
                        .offset(y: -h * 0.04)
                    }
                    .frame(width: w / 3, height: h * (0.55 + CGFloat((i * 7) % 3) * 0.07))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, h * 0.22)
            if let sign {
                Text(sign)
                    .font(.system(size: w * 0.06, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, w * 0.03)
                    .background(Color(red: 0.2, green: 0.2, blue: 0.25))
                    .offset(x: -w * 0.33, y: h * 0.12)
            }
            // trottoir et rue
            Rectangle().fill(Color(white: 0.7)).frame(height: h * 0.05).offset(y: h * 0.255)
            Rectangle().fill(Color(white: 0.35)).frame(height: h * 0.22).offset(y: h * 0.39)
            ForEach(0..<4) { i in
                Rectangle().fill(Color.white.opacity(0.7)).frame(width: w * 0.1, height: h * 0.01)
                    .offset(x: (CGFloat(i) - 1.5) * w * 0.26, y: h * 0.42)
            }
        }
    }

    private func park(_ w: CGFloat, _ h: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.7, green: 0.82, blue: 0.95), Color(red: 0.9, green: 0.93, blue: 0.95)], startPoint: .top, endPoint: .bottom)
            ForEach(0..<5) { i in
                Circle().fill(Color(red: 0.3, green: 0.55 + CGFloat(i % 2) * 0.1, blue: 0.3))
                    .frame(width: w * 0.32)
                    .offset(x: (CGFloat(i) - 2) * w * 0.22, y: -h * 0.02 - CGFloat(i % 2) * h * 0.06)
            }
            // grille du jardin
            ForEach(0..<14) { i in
                Rectangle().fill(Color(white: 0.15)).frame(width: 2, height: h * 0.2)
                    .offset(x: (CGFloat(i) - 6.5) * w * 0.075, y: h * 0.14)
            }
            Rectangle().fill(Color(white: 0.15)).frame(height: 3).offset(y: h * 0.05)
            Rectangle().fill(Color(red: 0.82, green: 0.78, blue: 0.68)).frame(height: h * 0.07).offset(y: h * 0.27)
            Rectangle().fill(Color(white: 0.38)).frame(height: h * 0.2).offset(y: h * 0.4)
        }
    }

    private func station(_ w: CGFloat, _ h: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.55, green: 0.6, blue: 0.7), Color(red: 0.8, green: 0.8, blue: 0.82)], startPoint: .top, endPoint: .bottom)
            RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.88, green: 0.85, blue: 0.8))
                .frame(width: w * 0.9, height: h * 0.45).offset(y: -h * 0.02)
            HStack(spacing: w * 0.04) {
                ForEach(0..<5) { _ in
                    UnevenRoundedRectangle(topLeadingRadius: w * 0.05, topTrailingRadius: w * 0.05)
                        .fill(Color(red: 0.3, green: 0.4, blue: 0.55).opacity(0.8))
                        .frame(width: w * 0.12, height: h * 0.25)
                }
            }
            .offset(y: h * 0.04)
            Text(T("GARE", "GARE"))
                .font(.system(size: w * 0.06, weight: .heavy, design: .serif))
                .foregroundStyle(Color(red: 0.2, green: 0.25, blue: 0.35))
                .offset(y: -h * 0.18)
            // horloge
            Circle().fill(Color.white).frame(width: w * 0.08).overlay(Circle().stroke(Color.black, lineWidth: 1.5)).offset(x: w * 0.3, y: -h * 0.18)
            Rectangle().fill(Color(white: 0.4)).frame(height: h * 0.22).offset(y: h * 0.39)
        }
    }
}


struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
        }
    }
}
