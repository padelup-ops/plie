import SwiftUI
import UIKit

enum AppLinks {
    /// Page de l'app sur l'App Store (active dès la publication).
    static let appStore = URL(string: "https://apps.apple.com/app/id6825605393")!
}

/// Image partagée après une victoire : le résultat sur une feuille de la couleur du jeu, collée sur le papier.
/// Dessinée en 360 × 450 points, rendue en 1080 × 1350 pixels.
struct ShareCard: View {
    let game: String
    let result: String
    let accent: Color

    var body: some View {
        ZStack {
            PaperBackdrop()
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(spacing: 12) {
                    Text(game)
                        .font(.paperTitle(26))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(result)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .minimumScaleFactor(0.5)
                }
                .foregroundStyle(Paper.ink)
                .padding(.horizontal, 26)
                .padding(.vertical, 36)
                .frame(width: 300)
                .background(PaperSheet(color: accent.paperTone(), cornerRadius: 26, ear: 36, lift: 1.4))
                .overlay(alignment: .top) { WashiTape(color: Paper.accent).offset(y: -13) }
                .rotationEffect(.degrees(-2))
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    OrigamoMark()
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: "Origamo")
                            .font(.paperTitle(24))
                            .foregroundStyle(Paper.ink)
                        Text(L("Joué sur iPhone Duo avec Origamo"))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Paper.inkSoft)
                    }
                }
            }
            .padding(28)
        }
        .frame(width: 360, height: 450)
        .environment(\.colorScheme, .light)
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
            renderer.scale = 3
            var list: [Any] = [L("\(game) : \(result). Je joue sur Origamo, des jeux pensés pour l'iPhone Duo.") + "\n" + AppLinks.appStore.absoluteString]
            if let image = renderer.uiImage { list.insert(image, at: 0) }
            items = list
            Haptics.tap()
        } label: {
            Label(L("Partager"), systemImage: "square.and.arrow.up")
                .font(.plie(15, weight: .bold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 16)
                .frame(minHeight: 40)
                .background(Capsule().fill(Theme.ghost))
                .overlay(Capsule().strokeBorder(Theme.faint, lineWidth: 1))
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

// MARK: - Le compteur des vrais arbres

/// Quand un joueur fait fleurir les 8 plantes de FERME, l'app envoie un seul message anonyme
/// (« un jardin de plus est complet ») au compteur d'Origamo. Rien n'identifie la personne.
enum TreeCounter {
    static let url = URL(string: "https://origamo.netlify.app/api/arbre")!

    static func send(completion: @escaping (Int?) -> Void) {
        guard BuildFlags.realTrees else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"event":"jardin-complet"}"#.utf8)
        request.timeoutInterval = 15
        let session = URLSession(configuration: .ephemeral)
        session.dataTask(with: request) { data, response, _ in
            var number: Int?
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                number = 0
                if let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let count = object["arbres"] as? Int {
                    number = count
                }
            }
            DispatchQueue.main.async { completion(number) }
        }.resume()
    }
}
