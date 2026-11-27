import AuthenticationServices
import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var server: ServerAPI
    @AppStorage(SeasonSetting.key) private var seasonMode = "auto"
    @AppStorage("serverURL") private var serverURL = ""
    @AppStorage("botServer") private var botServer = true

    var body: some View {
        Screen(title: "Profil") {
            if let me = server.me { profileCard(me) } else if server.isLoggedIn { ProgressView().frame(maxWidth: .infinity) } else { AuthPanel() }
            seasons
            settings
            about
        }
    }

    private func profileCard(_ me: APIMe) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Text(String((me.profile?.fullName ?? me.username).prefix(1)).uppercased())
                    .font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 56, height: 56).background(Circle().fill(UI.hero))
                VStack(alignment: .leading, spacing: 3) {
                    Text(me.profile?.fullName?.isEmpty == false ? me.profile!.fullName! : me.username).font(UI.title()).foregroundStyle(UI.ink)
                    Text("Niveau \(me.profile?.skillLevel ?? 1) · \(me.profile?.tierName ?? "Débutant")").font(UI.caption()).foregroundStyle(UI.muted)
                }
            }
            HStack(spacing: 10) {
                Metric(value: "\(me.stats?.matchesPlayed ?? 0)", label: "matchs")
                Metric(value: "\(me.stats?.matchesWon ?? 0)", label: "victoires")
                Metric(value: "\(Int((me.stats?.winRate ?? 0).rounded())) %", label: "réussite")
            }
            Button(role: .destructive) { server.logout() } label: { Text("Se déconnecter") }
                .buttonStyle(SecondaryButtonStyle(color: UI.danger))
        }
        .card()
    }

    private var seasons: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ambiance de saison").font(UI.headline()).foregroundStyle(UI.ink)
            Text("Feuilles en automne, neige à Noël, confettis au Nouvel An. L'idée de Yacine.").font(UI.caption()).foregroundStyle(UI.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    seasonChip("auto", "Auto")
                    ForEach(Season.allCases) { s in seasonChip(s.rawValue, s.name) }
                    seasonChip("off", "Aucune")
                }
            }
        }
        .card()
    }

    private func seasonChip(_ raw: String, _ label: String) -> some View {
        Button { seasonMode = raw } label: { Pill(text: label, active: seasonMode == raw) }.buttonStyle(.plain)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Réglages").font(UI.headline()).foregroundStyle(UI.ink)
            Toggle("Bot 24 h/24 sur le serveur PadelUp", isOn: $botServer).tint(UI.accent).font(UI.callout())
            VStack(alignment: .leading, spacing: 6) {
                Text("Serveur PadelUp").font(UI.caption()).foregroundStyle(UI.muted)
                InputField(title: "https://…/api (vide : serveur par défaut)", text: $serverURL, keyboard: .URL)
                Text(server.baseURL.absoluteString).font(UI.small()).foregroundStyle(UI.faint)
            }
        }
        .card()
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sources libres").font(UI.headline()).foregroundStyle(UI.ink)
            Group {
                Text("Clubs (\(CoverageZone.countries)) : © contributeurs OpenStreetMap, licence ODbL.")
                Text("Météo : Open-Meteo.com (CC BY 4.0).")
                Text("Disponibilités : Playtomic et Anybuddy, avec ton compte. PadelUp n'est affilié à aucune de ces plateformes.")
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                    .foregroundStyle(UI.faint)
            }
            .font(UI.caption()).foregroundStyle(UI.muted)
        }
        .card()
    }
}

struct AuthPanel: View {
    @EnvironmentObject private var server: ServerAPI
    @Environment(\.colorScheme) private var scheme
    @State private var mode = 0
    @State private var identifier = ""
    @State private var password = ""
    @State private var username = ""
    @State private var fullName = ""
    @State private var code = ""
    @State private var awaitingCode = false
    @State private var busy = false
    @State private var error: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ton compte PadelUp").font(UI.headline()).foregroundStyle(UI.ink)
                Text("Pour les matchs, le classement et le bot 24 h/24. Les clubs, la météo et le bot sur l'iPhone marchent sans compte.")
                    .font(UI.caption()).foregroundStyle(UI.muted)
            }
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                Task { await apple(result) }
            }
            .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
            .frame(height: 50)
            .clipShape(Capsule())
            Picker("", selection: $mode) { Text("Connexion").tag(0); Text("Inscription").tag(1) }.pickerStyle(.segmented)
            if awaitingCode {
                InputField(title: "Code reçu par e-mail", text: $code, keyboard: .numberPad)
            } else {
                if mode == 1 {
                    InputField(title: "Nom complet", text: $fullName)
                    InputField(title: "Nom d'utilisateur", text: $username)
                }
                InputField(title: mode == 0 ? "E-mail ou nom d'utilisateur" : "E-mail", text: $identifier, keyboard: .emailAddress)
                InputField(title: "Mot de passe", text: $password, secure: true)
            }
            if let error { Text(error).font(UI.caption()).foregroundStyle(UI.danger) }
            Button { Task { await submit() } } label: {
                if busy { ProgressView().tint(UI.onAccent) } else { Text(awaitingCode ? "Valider le code" : (mode == 0 ? "Se connecter" : "Créer mon compte")) }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(busy)
        }
        .card()
    }

    private func submit() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            if awaitingCode {
                try await server.verify(email: identifier, code: code.trimmingCharacters(in: .whitespaces))
            } else if mode == 0 {
                try await server.login(identifier: identifier.trimmingCharacters(in: .whitespaces), password: password)
            } else {
                awaitingCode = try await server.register(username: username, email: identifier.trimmingCharacters(in: .whitespaces),
                                                         password: password, fullName: fullName)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func apple(_ result: Result<ASAuthorization, Error>) async {
        guard case .success(let auth) = result, let cred = auth.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = cred.identityToken, let token = String(data: tokenData, encoding: .utf8) else { return }
        do {
            try await server.appleLogin(identityToken: token, firstName: cred.fullName?.givenName, lastName: cred.fullName?.familyName)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
