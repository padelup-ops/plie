import SwiftUI

// Outils de l'organisateur : modifier le match, inviter des amis.

struct EditMatchView: View {
    var match: APIMatch
    var onSaved: () -> Void = {}
    @EnvironmentObject private var server: ServerAPI
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var date = Date()
    @State private var duration = 90
    @State private var minLevel = 1
    @State private var maxLevel = 8
    @State private var isPublic = true
    @State private var busy = false
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            Screen(title: "Modifier le match", eyebrow: match.clubName, seasonal: false) {
                Block(title: "Le match") {
                    VStack(alignment: .leading, spacing: 16) {
                        InputField(title: "Titre", text: $title)
                        DatePicker("Date et heure", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                            .environment(\.locale, UI.fr).font(UI.body())
                        VStack(alignment: .leading, spacing: 8) {
                            Eyebrow(text: "Durée")
                            InlinePicker(options: [(60, "60 min"), (90, "90 min"), (120, "120 min")], selection: $duration)
                        }
                        HStack(spacing: 0) {
                            levelStepper("Niveau min", value: $minLevel, range: 1...maxLevel)
                            Rectangle().fill(UI.rule).frame(width: 0.5, height: 56).padding(.horizontal, 14)
                            levelStepper("Niveau max", value: $maxLevel, range: minLevel...10)
                        }
                        Toggle("Match public", isOn: $isPublic).tint(UI.court).font(UI.body())
                    }
                }
                Text("Les joueurs inscrits sont prévenus de chaque changement.").font(UI.caption()).foregroundStyle(UI.muted)
                if let error { Text(error).font(UI.callout()).foregroundStyle(UI.danger) }
                Button {
                    Task {
                        busy = true
                        defer { busy = false }
                        do {
                            try await server.updateMatch(match.id, title: title, date: date, duration: duration, minLevel: minLevel, maxLevel: maxLevel, isPublic: isPublic)
                            onSaved()
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                } label: { if busy { ProgressView().tint(UI.onCourt) } else { Text("Enregistrer") } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy)
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
        }
        .tint(UI.court)
        .onAppear {
            title = match.title ?? ""
            date = match.date ?? date
            duration = match.duration ?? 90
            minLevel = match.minSkillLevel ?? 1
            maxLevel = match.maxSkillLevel ?? 8
            isPublic = match.isPublic ?? true
        }
    }

    private func levelStepper(_ label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: label)
            HStack(spacing: 10) {
                Text("\(value.wrappedValue)").font(UI.score(30)).foregroundStyle(UI.ink)
                Stepper("", value: value, in: range).labelsHidden()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct InviteFriendsView: View {
    var match: APIMatch
    @EnvironmentObject private var server: ServerAPI
    @Environment(\.dismiss) private var dismiss
    @State private var friends: [APIPerson] = []
    @State private var picked: Set<Int> = []
    @State private var busy = false
    @State private var info: String? = nil
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            Screen(title: "Inviter", eyebrow: match.title ?? "Match de padel", seasonal: false) {
                if friends.isEmpty {
                    EmptyNote(title: "Pas encore d'amis à inviter.", message: "Ajoute tes partenaires depuis Profil → Mes amis, ou trouve-les sur le radar.")
                }
                VStack(spacing: 0) {
                    ForEach(Array(friends.enumerated()), id: \.element.id) { i, p in
                        Button {
                            if picked.contains(p.id) { picked.remove(p.id) } else { picked.insert(p.id) }
                        } label: {
                            PersonRow(person: p) {
                                Image(systemName: picked.contains(p.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22)).foregroundStyle(picked.contains(p.id) ? UI.court : UI.faint)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if i < friends.count - 1 { Hairline(inset: 56) }
                    }
                }
                if let info { Text(info).font(UI.callout()).foregroundStyle(UI.success) }
                if let error { Text(error).font(UI.callout()).foregroundStyle(UI.danger) }
                Button {
                    Task {
                        busy = true
                        defer { busy = false }
                        do {
                            try await server.invite(match: match.id, friends: Array(picked))
                            info = "Invitation\(picked.count > 1 ? "s" : "") envoyée\(picked.count > 1 ? "s" : "")."
                            try? await Task.sleep(nanoseconds: 800_000_000)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                } label: { if busy { ProgressView().tint(UI.onCourt) } else { Text(picked.isEmpty ? "Choisis des amis" : "Inviter \(picked.count) ami\(picked.count > 1 ? "s" : "")") } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy || picked.isEmpty)
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
        }
        .tint(UI.court)
        .task {
            if ShotMode.current != nil { friends = ShotMode.demoFriends().compactMap { $0.friend }; return }
            friends = ((try? await server.friends()) ?? []).compactMap { $0.friend }
        }
    }
}
