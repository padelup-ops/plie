// SetupView.swift — Allô Père Noël
//
// La personnalisation, sous la forme d'une lettre au Père Noël : une feuille crème, un cachet de cire, des lignes
// à remplir. Le prénom et les qualités suffisent ; l'âge, l'anecdote et le cadeau rendent l'appel plus personnel.
// On ne demande jamais rien de sensible (ni nom de famille, ni adresse, ni photo, ni genre).

import SwiftUI

struct SetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(MagicStore.self) private var store
    @FocusState private var focus: Field?

    enum Field: Hashable { case name(Int), anecdote, gift }

    private let ink = Noel.night
    private let maxAnecdote = 120

    var body: some View {
        @Bindable var model = model
        ZStack {
            NightScene(moon: true, trees: false)
            Snowfall(count: 40, opacity: 0.6)
            VStack(spacing: 0) {
                HStack {
                    Button { model.go(.home) } label: { RoundIcon(symbol: "chevron.left") }
                        .accessibilityLabel(Text("Back"))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                ScrollView {
                    letter
                        .padding(.horizontal, 18)
                        .padding(.top, 26)
                        .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)

                Button {
                    focus = nil
                    model.profile.save()
                    model.go(.scenario)
                } label: { Text("Continue ✨") }
                    .buttonStyle(MagicButtonStyle(glow: model.profile.isReady))
                    .disabled(!model.profile.isReady)
                    .opacity(model.profile.isReady ? 1 : 0.55)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 10)
            }
        }
    }

    // MARK: La lettre

    private var letter: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dear Santa,")
                    .font(.tale(30))
                    .foregroundStyle(ink)
                Text("this year, please call…")
                    .font(.story(19))
                    .foregroundStyle(Noel.bordeaux)
            }

            // Prénoms
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.profile.names.indices, id: \.self) { i in
                    HStack(spacing: 10) {
                        TextField(text: nameBinding(i), prompt: Text(i == 0 ? "First name" : "Another first name").foregroundStyle(ink.opacity(0.32))) {
                            Text("First name")
                        }
                        .font(.tale(28))
                        .foregroundStyle(ink)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focus, equals: .name(i))
                        if i > 0 {
                            Button {
                                withAnimation { _ = model.profile.names.remove(at: i) }
                            } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(ink.opacity(0.35))
                            }
                            .accessibilityLabel(Text("Remove"))
                        }
                    }
                    .padding(.bottom, 6)
                    .overlay(alignment: .bottom) { Rectangle().fill(Noel.gold).frame(height: 1.5) }
                    nameHint(i)
                }
                if model.profile.names.count < 4 {
                    Button {
                        if store.owned {
                            withAnimation { model.profile.names.append("") }
                            focus = .name(model.profile.names.count - 1)
                        } else {
                            model.sheet = .paywall
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                            Text("Add a brother or sister").multilineTextAlignment(.leading)
                            if !store.owned { PremiumTag().fixedSize() }
                        }
                        .font(.ui(15, .semibold))
                        .foregroundStyle(Noel.forest)
                    }
                    .padding(.top, 4)
                }
            }

            // Âge (un seul enfant)
            if !model.profile.isPlural {
                VStack(alignment: .leading, spacing: 10) {
                    label("Age")
                    HStack(spacing: 0) {
                        ForEach(3...10, id: \.self) { a in
                            Button {
                                withAnimation(.spring(duration: 0.3)) { model.profile.age = a }
                            } label: {
                                Text("\(a)")
                                    .font(.tale(18))
                                    .foregroundStyle(model.profile.age == a ? Noel.cream : ink)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(model.profile.age == a ? Noel.red : .clear))
                                    .overlay(Circle().strokeBorder(model.profile.age == a ? Noel.gold : ink.opacity(0.22), lineWidth: model.profile.age == a ? 2 : 1))
                                    .scaleEffect(model.profile.age == a ? 1.12 : 1)
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel(Text("\(a) years old"))
                        }
                    }
                }
            }

            // Qualités
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    label(model.profile.isPlural ? "What Santa heard about them" : "What Santa heard about this child")
                    Spacer()
                    Text("up to 2").font(.ui(13)).foregroundStyle(ink.opacity(0.5))
                }
                FlowLayout(spacing: 8) {
                    ForEach(Quality.allCases) { q in
                        let on = model.profile.qualities.contains(q)
                        let full = model.profile.qualities.count >= 2
                        Button {
                            withAnimation(.spring(duration: 0.3)) {
                                if on { model.profile.qualities.removeAll { $0 == q } }
                                else if !full { model.profile.qualities.append(q) }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: q.symbol).font(.system(size: 13, weight: .semibold))
                                Text(q.label).font(.ui(15, .semibold))
                            }
                            .foregroundStyle(on ? Noel.cream : ink)
                            .padding(.horizontal, 13).padding(.vertical, 9)
                            .background(Capsule().fill(on ? Noel.forest : ink.opacity(0.06)))
                            .overlay(Capsule().strokeBorder(on ? Noel.gold : .clear, lineWidth: 1.5))
                            .opacity(!on && full ? 0.45 : 1)
                        }
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }

            // Anecdote et cadeau (magie complète)
            premiumField(title: "A special moment this year", hint: "optional", field: .anecdote,
                         text: $model.profile.anecdote, prompt: anecdoteExample, limit: maxAnecdote, multiline: true)
            premiumField(title: model.profile.isPlural ? "Their Christmas wish" : "The Christmas wish", hint: "optional", field: .gift,
                         text: $model.profile.gift, prompt: "a red bike", limit: 50, multiline: false)

            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                Text("Everything stays on this iPhone.")
            }
            .font(.ui(13, .medium))
            .foregroundStyle(ink.opacity(0.55))
        }
        .padding(.horizontal, 24)
        .padding(.top, 38)
        .padding(.bottom, 28)
        .background(paper)
        .overlay(alignment: .top) { WaxSeal().offset(y: -26) }
    }

    /// Lien sûr vers un prénom (la ligne peut disparaître pendant qu'on la retire).
    private func nameBinding(_ i: Int) -> Binding<String> {
        Binding(
            get: { i < model.profile.names.count ? model.profile.names[i] : "" },
            set: { v in if i < model.profile.names.count { model.profile.names[i] = String(v.prefix(24)) } }
        )
    }

    /// Le Père Noël a enregistré ce prénom, ou bien c'est son lutin qui le dira : le parent le sait avant l'appel.
    @ViewBuilder
    private func nameHint(_ i: Int) -> some View {
        let name = i < model.profile.names.count ? model.profile.names[i].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        if name.count >= 2 {
            let lang = ScriptBook.load().1
            let knows = !VoiceLibrary.shared.ready(lang: lang) || VoiceLibrary.shared.knows(name: name, lang: lang)
            HStack(spacing: 5) {
                Image(systemName: knows ? "checkmark.seal.fill" : "sparkles")
                Text(knows ? "Santa will say this first name himself." : "Santa hasn't recorded this first name yet: he will say hello without it.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.ui(12, .medium))
            .foregroundStyle(knows ? Noel.forest : ink.opacity(0.55))
            .transition(.opacity)
        }
    }

    private var anecdoteExample: LocalizedStringKey {
        model.profile.isPlural ? "They helped decorate the tree" : "She learned to ride a bike"
    }

    private func label(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.story(18))
            .foregroundStyle(Noel.bordeaux)
    }

    @ViewBuilder
    private func premiumField(title: LocalizedStringKey, hint: LocalizedStringKey, field: Field, text: Binding<String>,
                              prompt: LocalizedStringKey, limit: Int, multiline: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                label(title)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                Text(hint).font(.ui(13)).foregroundStyle(ink.opacity(0.45)).fixedSize()
                if !store.owned { PremiumTag().fixedSize() }
            }
            ZStack(alignment: .leading) {
                TextField(text: text, prompt: Text(prompt).foregroundStyle(ink.opacity(0.32)), axis: multiline ? .vertical : .horizontal) { Text(title) }
                    .font(.story(20))
                    .foregroundStyle(ink)
                    .lineLimit(multiline ? 1...3 : 1...1)
                    .focused($focus, equals: field)
                    .disabled(!store.owned)
                    .onChange(of: text.wrappedValue) { _, v in
                        if v.count > limit { text.wrappedValue = String(v.prefix(limit)) }
                    }
                if !store.owned {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { model.sheet = .paywall }
                }
            }
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) { Rectangle().fill(Noel.gold).frame(height: 1.5) }
        }
    }

    private var paper: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(LinearGradient(colors: [Noel.cream, Color(red: 0.98, green: 0.93, blue: 0.84)], startPoint: .top, endPoint: .bottom))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Noel.gold.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .padding(8)
            )
            .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
    }
}

/// Le cachet de cire rouge, une étoile dorée au centre.
struct WaxSeal: View {
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(red: 0.80, green: 0.18, blue: 0.20), Noel.bordeaux], center: .init(x: 0.4, y: 0.35), startRadius: 2, endRadius: 34))
                .frame(width: 56, height: 56)
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            Circle().strokeBorder(Noel.bordeaux.opacity(0.8), lineWidth: 3).frame(width: 44, height: 44)
            StarShape().fill(Noel.goldGradient).frame(width: 24, height: 24)
        }
        .accessibilityHidden(true)
    }
}

/// « Pass Noël » : ce qui demande le Pass.
struct PremiumTag: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold))
            Text("Christmas Pass").font(.ui(11, .bold))
        }
        .foregroundStyle(Noel.night)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(Noel.goldGradient))
    }
}

/// Les étiquettes qui passent à la ligne (les qualités).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
        }
        return CGSize(width: width, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}
