import AuthenticationServices
import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var server: ServerAPI
    @EnvironmentObject private var router: Router
    @AppStorage(SeasonSetting.key) private var seasonMode = "auto"
    @AppStorage("serverURL") private var serverURL = ""
    @AppStorage("botServer") private var botServer = true

    var body: some View {
        Screen(title: server.me == nil ? "Profil" : displayName, eyebrow: server.me == nil ? nil : levelLine) {
            if let me = server.me {
                identity(me)
                accountBlock(me)
            } else if server.isLoggedIn {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                AuthPanel()
            }
            seasonBlock
            settingsBlock
            aboutBlock
            if server.me != nil && ShotMode.current == nil {
                Button("Se déconnecter") { server.logout() }.buttonStyle(LinkButtonStyle(color: UI.danger))
            }
        }
    }

    private var displayName: String {
        guard let me = server.me else { return "Profil" }
        return me.profile?.fullName?.isEmpty == false ? me.profile!.fullName! : me.username
    }

    private var levelLine: String {
        let p = server.me?.profile
        return "Niveau \(p?.skillLevel ?? 1) · " + (p?.tierName ?? PadelLevel.name(p?.skillLevel ?? 1, scale: p?.evaluationType ?? "new"))
    }

    private func identity(_ me: APIMe) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                Avatar(name: displayName, size: 64)
                VStack(alignment: .leading, spacing: 6) {
                    LevelBars(level: me.profile?.skillLevel ?? 1, count: me.profile?.evaluationType == "old" ? 10 : 8, height: 20, barWidth: 5)
                    Text([me.profile?.location, me.profile?.rightHanded == false ? "gaucher" : "droitier"].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(UI.caption()).foregroundStyle(UI.muted)
                }
            }
            StatsRow(items: [
                ("\(me.stats?.matchesPlayed ?? 0)", "matchs"),
                ("\(me.stats?.matchesWon ?? 0)", "victoires"),
                ("\(Int((me.stats?.winRate ?? 0).rounded())) %", "réussite"),
            ])
        }
    }

    private func accountBlock(_ me: APIMe) -> some View {
        Block(title: "Mon jeu") {
            VStack(spacing: 0) {
                Button { router.showLevel = true } label: {
                    ListRow(title: "Mon niveau", value: me.profile?.skillLevel.map { "\($0) · " + PadelLevel.name($0, scale: me.profile?.evaluationType ?? "new") } ?? "À choisir",
                            systemImage: "chart.bar")
                }
                .buttonStyle(.plain)
                Hairline(inset: 36)
                Button { router.showFriends = true } label: { ListRow(title: "Mes amis", systemImage: "person.2") }.buttonStyle(.plain)
                Hairline(inset: 36)
                Button { router.showNotifications = true } label: { ListRow(title: "Notifications", systemImage: "bell") }.buttonStyle(.plain)
                Hairline(inset: 36)
                Button { router.sheet = .community } label: { ListRow(title: "Communauté", systemImage: "bubble.left.and.bubble.right") }.buttonStyle(.plain)
                Hairline(inset: 36)
                Button { router.sheet = .bookings } label: { ListRow(title: "Mes réservations", detail: "Clubs partenaires PadelUp", systemImage: "calendar") }.buttonStyle(.plain)
                Hairline(inset: 36)
                Button { router.sheet = .editProfile } label: { ListRow(title: "Modifier mon profil", detail: "Nom, présentation, ville, mot de passe, suppression du compte", systemImage: "person.text.rectangle") }.buttonStyle(.plain)
            }
        }
    }

    private var seasonBlock: some View {
        Block(title: "Ambiance", meta: "l'idée de Yacine") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Feuilles en automne, neige à Noël, confettis au Nouvel An : elles tombent derrière les écrans.")
                    .font(UI.callout()).foregroundStyle(UI.muted).fixedSize(horizontal: false, vertical: true)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        seasonChip("auto", "Selon la date")
                        ForEach(Season.allCases) { s in seasonChip(s.rawValue, s.name) }
                        seasonChip("off", "Aucune")
                    }
                }
            }
        }
    }

    private func seasonChip(_ raw: String, _ label: String) -> some View {
        Button { withAnimation(.snappy(duration: 0.2)) { seasonMode = raw } } label: { Chip(text: label, active: seasonMode == raw) }.buttonStyle(.plain)
    }

    private var settingsBlock: some View {
        Block(title: "Réglages") {
            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: $botServer) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Bot 24 h/24 sur le serveur PadelUp").font(UI.body()).foregroundStyle(UI.ink)
                        Text("Pour les clubs partenaires PadelUp. Playtomic et Anybuddy se lisent depuis ton iPhone.").font(UI.caption()).foregroundStyle(UI.muted)
                    }
                }
                .tint(UI.court)
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Serveur PadelUp")
                    InputField(title: "https://…/api (vide : serveur par défaut)", text: $serverURL, keyboard: .URL)
                    Text(server.baseURL.absoluteString).font(UI.small()).foregroundStyle(UI.faint)
                }
            }
        }
    }

    private var aboutBlock: some View {
        Block(title: "Sources", actionTitle: "Diagnostic", action: { router.sheet = .diagnostic }) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Clubs (\(CoverageZone.countries)) : © contributeurs OpenStreetMap, licence ODbL.")
                Text("Météo : Open-Meteo.com (CC BY 4.0).")
                Text("Playtomic et Anybuddy : lus avec ton compte, depuis ton iPhone. PadelUp n'est affilié à aucune de ces plateformes.")
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                    .foregroundStyle(UI.faint)
            }
            .font(UI.caption()).foregroundStyle(UI.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
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
    @State private var info: String? = nil
    @State private var forgot = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ton compte PadelUp").font(UI.title(22)).foregroundStyle(UI.ink)
                Text("Pour les matchs, les amis et le classement. Les clubs, la météo et le bot marchent sans compte.")
                    .font(UI.callout()).foregroundStyle(UI.muted).fixedSize(horizontal: false, vertical: true)
            }
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                Task { await apple(result) }
            }
            .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
            .frame(height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            HStack(spacing: 12) {
                Hairline()
                Text("ou").font(UI.caption()).foregroundStyle(UI.faint)
                Hairline()
            }
            UnderlineTabs(items: ["Connexion", "Inscription"], selection: $mode)
            VStack(spacing: 10) {
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
            }
            if let error { Text(error).font(UI.callout()).foregroundStyle(UI.danger) }
            if let info { Text(info).font(UI.callout()).foregroundStyle(UI.success) }
            Button { Task { await submit() } } label: {
                if busy { ProgressView().tint(UI.onCourt) } else { Text(awaitingCode ? "Valider le code" : (mode == 0 ? "Se connecter" : "Créer mon compte")) }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(busy)
            HStack {
                if awaitingCode {
                    Button("Renvoyer le code") {
                        Task {
                            do { try await server.resendCode(email: identifier.trimmingCharacters(in: .whitespaces)); info = "Nouveau code envoyé." }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                    .buttonStyle(LinkButtonStyle())
                } else if mode == 0 {
                    Button("Mot de passe oublié ?") { forgot = true }.buttonStyle(LinkButtonStyle(color: UI.muted))
                }
                Spacer()
            }
        }
        .sheet(isPresented: $forgot) { ForgotPasswordView(email: identifier.contains("@") ? identifier : "") }
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
