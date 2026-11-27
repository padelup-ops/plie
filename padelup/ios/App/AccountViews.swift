import SwiftUI

// Compte : modifier son profil, mot de passe (changer, oublié), supprimer son compte, mes réservations.

struct EditProfileView: View {
    @EnvironmentObject private var server: ServerAPI
    @Environment(\.dismiss) private var dismiss
    @State private var fullName = ""
    @State private var bio = ""
    @State private var city = ""
    @State private var rightHanded = true
    @State private var busy = false
    @State private var error: String? = nil
    @State private var showPassword = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Screen(title: "Mon profil", seasonal: false) {
                Block(title: "Identité") {
                    VStack(alignment: .leading, spacing: 10) {
                        InputField(title: "Nom complet", text: $fullName)
                        TextField("Quelques mots sur ton jeu (facultatif)", text: $bio, axis: .vertical)
                            .lineLimit(3...6)
                            .font(UI.body())
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(UI.raised))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(UI.rule, lineWidth: 1))
                        InputField(title: "Ville", text: $city, systemImage: "mappin")
                        VStack(alignment: .leading, spacing: 8) {
                            Eyebrow(text: "Main")
                            InlinePicker(options: [(true, "Droitier"), (false, "Gaucher")], selection: $rightHanded)
                        }
                    }
                }
                if let error { Text(error).font(UI.callout()).foregroundStyle(UI.danger) }
                Button { Task { await save() } } label: {
                    if busy { ProgressView().tint(UI.onCourt) } else { Text("Enregistrer") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy)
                Block(title: "Sécurité") {
                    VStack(spacing: 0) {
                        Button { showPassword = true } label: { ListRow(title: "Changer de mot de passe", systemImage: "key") }.buttonStyle(.plain)
                        Hairline(inset: 36)
                        Button { confirmDelete = true } label: {
                            ListRow(title: "Supprimer mon compte", detail: "Efface ton profil, tes matchs et tes messages.", systemImage: "trash",
                                    chevron: false, titleColor: UI.danger)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
            .sheet(isPresented: $showPassword) { ChangePasswordView() }
            .confirmationDialog("Supprimer ton compte PadelUp ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer définitivement", role: .destructive) {
                    Task {
                        do { try await server.deleteAccount(); dismiss() } catch { self.error = error.localizedDescription }
                    }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Ton profil, tes matchs, tes amis et tes messages seront effacés. C'est irréversible.")
            }
        }
        .tint(UI.court)
        .onAppear {
            let p = server.me?.profile
            fullName = p?.fullName ?? ""
            bio = p?.bio ?? ""
            city = p?.location ?? ""
            rightHanded = p?.rightHanded ?? true
        }
    }

    private func save() async {
        if ShotMode.current != nil { dismiss(); return }
        busy = true
        defer { busy = false }
        do {
            try await server.updateProfileDetails(fullName: fullName.trimmingCharacters(in: .whitespaces), bio: bio,
                                                  location: city.trimmingCharacters(in: .whitespaces), rightHanded: rightHanded)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct ChangePasswordView: View {
    @EnvironmentObject private var server: ServerAPI
    @Environment(\.dismiss) private var dismiss
    @State private var old = ""
    @State private var new = ""
    @State private var busy = false
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            Screen(title: "Mot de passe", seasonal: false) {
                VStack(spacing: 10) {
                    InputField(title: "Mot de passe actuel", text: $old, secure: true)
                    InputField(title: "Nouveau mot de passe (8 caractères ou plus)", text: $new, secure: true)
                }
                if let error { Text(error).font(UI.callout()).foregroundStyle(UI.danger) }
                Button {
                    Task {
                        busy = true
                        defer { busy = false }
                        do { try await server.changePassword(old: old, new: new); dismiss() } catch { self.error = error.localizedDescription }
                    }
                } label: { if busy { ProgressView().tint(UI.onCourt) } else { Text("Changer le mot de passe") } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy || old.isEmpty || new.count < 8)
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
        }
        .tint(UI.court)
    }
}

struct ForgotPasswordView: View {
    var email: String = ""
    @EnvironmentObject private var server: ServerAPI
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var code = ""
    @State private var newPassword = ""
    @State private var sent = false
    @State private var busy = false
    @State private var info: String? = nil
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            Screen(title: "Mot de passe oublié", seasonal: false) {
                Text(sent ? "Entre le code reçu par e-mail (valable 15 minutes) et ton nouveau mot de passe."
                          : "On t'envoie un code par e-mail pour choisir un nouveau mot de passe.")
                    .font(UI.callout()).foregroundStyle(UI.muted).fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 10) {
                    InputField(title: "E-mail", text: $address, keyboard: .emailAddress)
                    if sent {
                        InputField(title: "Code à 6 chiffres", text: $code, keyboard: .numberPad)
                        InputField(title: "Nouveau mot de passe", text: $newPassword, secure: true)
                    }
                }
                if let info { Text(info).font(UI.callout()).foregroundStyle(UI.success) }
                if let error { Text(error).font(UI.callout()).foregroundStyle(UI.danger) }
                Button { Task { await submit() } } label: {
                    if busy { ProgressView().tint(UI.onCourt) } else { Text(sent ? "Changer le mot de passe" : "Recevoir le code") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy || !address.contains("@"))
                if sent {
                    Button("Renvoyer le code") { sent = false; Task { await submit() } }.buttonStyle(LinkButtonStyle())
                }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
        }
        .tint(UI.court)
        .onAppear { if address.isEmpty { address = email } }
    }

    private func submit() async {
        busy = true
        error = nil
        defer { busy = false }
        let mail = address.trimmingCharacters(in: .whitespaces)
        do {
            if !sent {
                try await server.requestPasswordReset(email: mail)
                sent = true
                info = "Si un compte existe avec cette adresse, un code vient d'être envoyé."
            } else {
                try await server.confirmPasswordReset(email: mail, code: code.trimmingCharacters(in: .whitespaces), newPassword: newPassword)
                info = "Mot de passe changé. Connecte-toi avec le nouveau."
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                dismiss()
            }
        } catch { self.error = error.localizedDescription }
    }
}

/// Mes réservations dans les clubs partenaires PadelUp.
struct BookingsView: View {
    @EnvironmentObject private var server: ServerAPI
    @Environment(\.dismiss) private var dismiss
    @State private var bookings: [APIBooking] = []
    @State private var loaded = false
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            Screen(title: "Réservations", eyebrow: "Clubs partenaires PadelUp", seasonal: false) {
                let upcoming = bookings.filter { $0.isUpcoming }
                let past = bookings.filter { !$0.isUpcoming }
                if loaded && bookings.isEmpty {
                    EmptyNote(title: "Aucune réservation.", message: "Les terrains réservés dans les clubs partenaires PadelUp apparaissent ici. Les réservations Playtomic et Anybuddy restent dans leurs apps.")
                }
                if let error { Text(error).font(UI.callout()).foregroundStyle(UI.danger) }
                if !upcoming.isEmpty {
                    Block(title: "À venir") {
                        VStack(spacing: 0) {
                            ForEach(upcoming) { b in
                                bookingRow(b, cancellable: true)
                                Hairline(inset: 70)
                            }
                        }
                    }
                }
                if !past.isEmpty {
                    Block(title: "Passées et annulées") {
                        VStack(spacing: 0) {
                            ForEach(past.prefix(20)) { b in
                                bookingRow(b, cancellable: false).opacity(0.6)
                                Hairline(inset: 70)
                            }
                        }
                    }
                }
            }
            .refreshable { await load() }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
        }
        .tint(UI.court)
        .task { await load() }
    }

    private func bookingRow(_ b: APIBooking, cancellable: Bool) -> some View {
        HStack(spacing: 16) {
            DateBlock(date: b.day)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(b.startTime.prefix(5))\(b.endTime.map { "–" + $0.prefix(5) } ?? "")").font(UI.score(18)).foregroundStyle(UI.ink)
                Text(b.clubName ?? "Club").font(UI.headline()).foregroundStyle(UI.ink)
                Text([b.courtName ?? "", b.totalAmount.map { "\($0) \(b.currency ?? "€")" } ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(UI.caption()).foregroundStyle(UI.muted)
            }
            Spacer()
            if cancellable {
                Menu {
                    Button("Annuler la réservation", role: .destructive) { Task { try? await server.cancelBooking(b.id); await load() } }
                } label: { Image(systemName: "ellipsis").foregroundStyle(UI.muted).frame(width: 32, height: 32) }
            } else if b.status == "cancelled" {
                Stamp(text: "Annulée", style: .outline)
            }
        }
        .padding(.vertical, 12)
    }

    private func load() async {
        guard server.isLoggedIn, ShotMode.current == nil else { loaded = true; return }
        do { bookings = try await server.myBookings(); error = nil } catch { self.error = error.localizedDescription }
        loaded = true
    }
}
