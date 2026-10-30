import SwiftUI

// MARK: - Le sondage de la bêta
//
// Seulement dans les versions de test (TestFlight) :
// - à l'ouverture, un écran « Ton avis en 1 minute », au plus une fois par jour, tant que le testeur n'a pas répondu ;
// - sur l'accueil, une carte qu'on peut écarter 3 jours.
// La page du site renvoie vers clapet://sondage-fait une fois la réponse envoyée : l'app sait alors que c'est fait.
// On ne bloque jamais l'app (« Plus tard » est toujours possible) : Apple interdit d'obliger à répondre.

enum SurveyRule {
    /// Change cet identifiant pour proposer un nouveau sondage aux testeurs.
    static let id = "beta-2026-10"
    private static var answeredKey: String { "survey.\(id).answered" }
    private static var presentedDayKey: String { "survey.\(id).presentedDay" }
    private static var cardHiddenKey: String { "survey.\(id).cardHiddenUntil" }

    private static var defaults: UserDefaults { .standard }

    private static func available(_ isTestBuild: Bool) -> Bool {
        isTestBuild && !Demo.seeded && Demo.screen == nil && !defaults.bool(forKey: answeredKey)
    }

    private static var today: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    /// L'écran plein, à l'ouverture : une fois par jour au plus.
    static func shouldPresent(isTestBuild: Bool) -> Bool {
        available(isTestBuild) && defaults.string(forKey: presentedDayKey) != today
    }

    static func markPresented() {
        defaults.set(today, forKey: presentedDayKey)
    }

    /// La carte de l'accueil.
    static func shouldShowCard(isTestBuild: Bool) -> Bool {
        available(isTestBuild) && Date().timeIntervalSince1970 >= defaults.double(forKey: cardHiddenKey)
    }

    static func hideCard() {
        defaults.set(Date().addingTimeInterval(3 * 86_400).timeIntervalSince1970, forKey: cardHiddenKey)
    }

    /// Appelé par le lien clapet://sondage-fait de la page de remerciement.
    static func markAnswered() {
        defaults.set(true, forKey: answeredKey)
    }

    static func isAnswerLink(_ url: URL) -> Bool { url.host == "sondage-fait" }

    /// La page du sondage, dans la langue de l'app, avec le numéro du build.
    static var url: URL {
        let french = Bundle.main.preferredLocalizations.first?.hasPrefix("fr") == true
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let page = french ? "fr/sondage.html" : "en/survey.html"
        return URL(string: "https://foldly.netlify.app/\(page)?src=app&build=\(build)")!
    }
}

/// L'écran plein, à l'ouverture.
struct SurveyScreen: View {
    var onAnswer: () -> Void
    var onLater: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            VStack(spacing: 18) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(Color.dfAccent)
                Text("Your take in 1 minute")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("Foldly is still in beta and you're one of its first users. 6 quick questions help me choose what to build next.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 10) {
                    point("checklist", Text("6 questions, about 1 minute"))
                    point("hand.raised.fill", Text("Anonymous, unless you leave your email"))
                    point("sparkles", Text("You pick the next feature"))
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: 420)
            Spacer(minLength: 24)
            VStack(spacing: 10) {
                Button(action: onAnswer) {
                    Label { Text("Answer the survey") } icon: { Image(systemName: "arrow.up.right") }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.dfAccent)
                .foregroundStyle(Color.dfOnAccent)
                Button(action: onLater) {
                    Text("Later")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: 420)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dfBackground.ignoresSafeArea())
    }

    private func point(_ symbol: String, _ text: Text) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.dfAccent)
                .frame(width: 26)
            text.font(.subheadline)
        }
    }
}

/// La carte de l'accueil : « Ton avis en 1 minute ».
struct SurveyPromo: View {
    var onOpen: () -> Void
    var onHide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "text.bubble.fill")
                    .font(.title2)
                    .foregroundStyle(Color.dfAccent)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your take in 1 minute")
                        .font(.headline)
                    Text("6 quick questions to choose what Foldly gets next.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(action: onHide) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.dfFill))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Not now"))
            }
            Button(action: onOpen) {
                Label { Text("Answer the survey") } icon: { Image(systemName: "arrow.up.right") }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.dfAccent)
            .foregroundStyle(Color.dfOnAccent)
        }
    }
}
