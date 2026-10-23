import SwiftUI
import UIKit

enum AppLinks {
    /// Page de l'app sur l'App Store (active dès la publication).
    static let appStore = URL(string: "https://apps.apple.com/app/id6825605393")!
}

/// Image partagée après une victoire : le jeu, le résultat, le logo, le lien.
struct ShareCard: View {
    let game: String
    let result: String
    let accent: Color

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x23275C), Color(hex: 0x0B0C1C)], startPoint: .top, endPoint: .bottom)
            Circle().fill(accent.opacity(0.45)).frame(width: 760, height: 760).blur(radius: 140).offset(x: -240, y: -360)
            Circle().fill(Theme.paint.opacity(0.3)).frame(width: 640, height: 640).blur(radius: 140).offset(x: 260, y: 380)
            VStack(spacing: 34) {
                Image("Logo")
                    .resizable()
                    .frame(width: 300, height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 68, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 30, y: 16)
                Text(game)
                    .font(.system(size: 66, weight: .black, design: .rounded))
                    .foregroundStyle(accent)
                Text(result)
                    .font(.system(size: 88, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 60)
                Text(L("Joué sur iPhone Duo avec Origamo"))
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                Text("ORIGAMO")
                    .font(.system(size: 54, weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [Theme.laser, Theme.paint, Theme.gold], startPoint: .leading, endPoint: .trailing))
            }
        }
        .frame(width: 1080, height: 1350)
    }
}

/// Bouton « Partager » : image du résultat et lien vers l'App Store.
struct ShareResultButton: View {
    let game: String
    let result: String
    var accent: Color = Theme.laser

    @State private var items: [Any]?

    var body: some View {
        Button {
            let renderer = ImageRenderer(content: ShareCard(game: game, result: result, accent: accent))
            renderer.scale = 1
            var list: [Any] = [L("\(game) : \(result). Je joue sur Origamo, des jeux pensés pour l'iPhone Duo.") + "\n" + AppLinks.appStore.absoluteString]
            if let image = renderer.uiImage { list.insert(image, at: 0) }
            items = list
            Haptics.tap()
        } label: {
            Label(L("Partager"), systemImage: "square.and.arrow.up")
                .font(.plie(15, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(minHeight: 40)
                .background(Capsule().fill(Color.white.opacity(0.14)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .sheet(isPresented: Binding(get: { items != nil }, set: { if !$0 { items = nil } })) {
            ActivitySheet(items: items ?? [])
                .presentationDetents([.medium, .large])
        }
    }
}

struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
