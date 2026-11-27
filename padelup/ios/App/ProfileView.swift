import AuthenticationServices
import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var server: ServerAPI
    @AppStorage(SeasonSetting.key) private var seasonMode = "auto"
    @AppStorage("serverURL") private var serverURL = ""
    @AppStorage("botServer") private var botServer = true

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground(intensity: 0.4)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ScreenHeader(title: "Profil")
                        if let me = server.me { profileCard(me) } else if server.isLoggedIn { ProgressView().tint(Neo.volt) } else { AuthPanel() }
                        settings
                        about
                    }
                    .padding(18)
                    .padding(.bottom, 40)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func profileCard(_ me: APIMe) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Text(String((me.profile?.fullName ?? me.username).prefix(1)).uppercased())
                    .font(Neo.title(26)).foregroundStyle(Neo.night)
                    .frame(width: 64, height: 64).background(Circle().fill(Neo.neonGradient)).neonGlow(Neo.cyan, radius: 10)
                VStack(alignment: .leading, spacing: 4) {
                    Text(me.profile?.fullName?.isEmpty == false ? me.profile!.fullName! : me.username).font(Neo.title(20)).foregroundStyle(Neo.text)
                    Text("Niveau \(me.profile?.skillLevel ?? 1) · \(me.profile?.tierName ?? "Débutant")").font(Neo.label(12)).foregroundStyle(Neo.volt)
                    if let loc = me.profile?.location, !loc.isEmpty { Text(loc).font(Neo.body(12)).foregroundStyle(Neo.dim) }
                }
            }
            HStack(spacing: 10) {
                StatTile(value: "\(me.stats?.matchesPlayed ?? 0)", label: "matchs", color: Neo.cyan)
                StatTile(value: "\(me.stats?.matchesWon ?? 0)", label: "victoires", color: Neo.volt)
                StatTile(value: "\(Int((me.stats?.winRate ?? 0).rounded())) %", label: "réussite", color: Neo.magenta)
            }
            Button(role: .destructive) { server.logout() } label: { Text("Se déconnecter") }
                .buttonStyle(NeonButtonStyle(color: Neo.danger, filled: false))
        }
        .glassCard()
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "Ambiance de saison")
            Text("Feuilles en automne, neige à Noël, confettis au Nouvel An… L'idée de Yacine 🍂❄︎").font(Neo.body(13)).foregroundStyle(Neo.dim)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    seasonChip("auto", "Auto")
                    ForEach(Season.allCases) { s in seasonChip(s.rawValue, s.name) }
                    seasonChip("off", "Désactivé")
                }
            }
            Divider().overlay(Neo.line)
            SectionTitle(text: "Bot")
            Toggle("Bot 24 h/24 sur le serveur PadelUp", isOn: $botServer).tint(Neo.volt).font(Neo.body(14))
            Divider().overlay(Neo.line)
            SectionTitle(text: "Serveur PadelUp")
            TextField("https://…/api (laisser vide : serveur par défaut)", text: $serverURL)
                .font(Neo.mono(13)).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
            Text("Actuel : \(server.baseURL.absoluteString)").font(Neo.body(11)).foregroundStyle(Neo.faint)
        }
        .glassCard()
    }

    private func seasonChip(_ raw: String, _ label: String) -> some View {
        Button { seasonMode = raw } label: { Chip(text: label, selected: seasonMode == raw, color: Season(rawValue: raw)?.tint ?? Neo.cyan) }
            .buttonStyle(.plain)
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "Sources libres")
            Text("Clubs (\(CoverageZone.countries)) : © contributeurs OpenStreetMap, licence ODbL (openstreetmap.org/copyright).").font(Neo.body(12))
            Text("Météo : Open-Meteo.com (CC BY 4.0).").font(Neo.body(12))
            Text("Disponibilités : Playtomic et Anybuddy, avec ton compte. PadelUp n'est affilié à aucune de ces plateformes.").font(Neo.body(12))
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                .font(Neo.mono(11)).foregroundStyle(Neo.faint)
        }
        .foregroundStyle(Neo.dim)
        .glassCard()
    }
}

struct AuthPanel: View {
    @EnvironmentObject private var server: ServerAPI
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
            Text("Ton compte PadelUp").font(Neo.label(15)).foregroundStyle(Neo.text)
            Text("Matchs, classement et bot 24 h/24. Les clubs, la météo et le bot sur l'iPhone marchent sans compte.")
                .font(Neo.body(13)).foregroundStyle(Neo.dim)
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                Task { await apple(result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 50)
            .clipShape(Capsule())
            Picker("", selection: $mode) { Text("Connexion").tag(0); Text("Inscription").tag(1) }.pickerStyle(.segmented)
            if awaitingCode {
                field("Code reçu par e-mail", text: $code).keyboardType(.numberPad)
            } else {
                if mode == 1 {
                    field("Nom complet", text: $fullName)
                    field("Nom d'utilisateur", text: $username)
                }
                field(mode == 0 ? "E-mail ou nom d'utilisateur" : "E-mail", text: $identifier).keyboardType(.emailAddress)
                SecureField("Mot de passe", text: $password).font(Neo.body(16)).padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))
            }
            if let error { Text(error).font(Neo.body(13)).foregroundStyle(Neo.danger) }
            Button { Task { await submit() } } label: {
                if busy { ProgressView().tint(Neo.night) } else { Text(awaitingCode ? "Valider le code" : (mode == 0 ? "Se connecter" : "Créer mon compte")) }
            }
            .buttonStyle(NeonButtonStyle(color: Neo.volt))
            .disabled(busy)
        }
        .glassCard()
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text).font(Neo.body(16)).textInputAutocapitalization(.never).autocorrectionDisabled().padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))
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
