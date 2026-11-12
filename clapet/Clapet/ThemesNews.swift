import SwiftUI

// MARK: - Les 2 000 : deux nouveaux thèmes, Bento et Atelier
//
// Annoncé une fois. Avec Foldly+ ils sont inclus ; sans, 3 jours d'essai (ThemeTrial), puis Foldly+.

enum ThemesNews {
    static let key = "themesNewsSeen"
    static var seen: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

struct ThemesNewsView: View {
    @Environment(ClapetStore.self) private var store
    @Environment(ClapetModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DFLook.key) private var lookRaw = ""
    @State private var shown = false
    @State private var showPlus = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    Text("2,000 downloads: thank you!")
                        .font(.footnote.weight(.bold))
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .foregroundStyle(Color(red: 0.18, green: 0.545, blue: 0.416))
                    Text("Two new themes")
                        .font(.system(.largeTitle, design: .serif).weight(.bold))
                        .multilineTextAlignment(.center)
                    Text("Bento and Atelier: move your cards wherever you want, hide the ones you don't need, and pick your color.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 28)
                .padding(.horizontal, 24)

                HStack(spacing: 14) {
                    preview(.bento)
                    preview(.atelier)
                }
                .padding(.horizontal, 20)
                .scaleEffect(shown ? 1 : 0.92)
                .opacity(shown ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.75), value: shown)

                VStack(spacing: 10) {
                    Label { Text("Hold and drop to move a card") } icon: { Image(systemName: "hand.draw") }
                    Label { Text("Tap − to hide a card, + to bring it back") } icon: { Image(systemName: "minus.circle") }
                    Label { Text("Seven colors for each theme") } icon: { Image(systemName: "paintpalette") }
                    Label { Text("Book and L positions keep their own layout") } icon: { Image(systemName: "laptopcomputer") }
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 32)

                Text(store.hasPlus ? LocalizedStringKey("Included in your Foldly+.") : LocalizedStringKey("Free for 3 days, then part of Foldly+ (one-time purchase)."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Button { dismiss() } label: {
                    Text("Later").font(.subheadline.weight(.medium)).frame(minHeight: 44)
                }
                .padding(.bottom, 16)
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            ThemesNews.seen = true
            shown = true
        }
        .sheet(isPresented: $showPlus) {
            PlusView(reason: PlusReason.theme.text(model.stats)).environment(model).environment(store)
        }
    }

    private func preview(_ look: DFLook) -> some View {
        let atelier = look == .atelier
        let bg = atelier ? Color(red: 0.96, green: 0.953, blue: 0.937) : Color(red: 0.97, green: 0.97, blue: 0.96)
        let accent = atelier ? Color(red: 0.18, green: 0.545, blue: 0.416) : Color(red: 0.18, green: 0.36, blue: 1.0)
        let hero = atelier ? Color(red: 0.12, green: 0.165, blue: 0.14) : Color(red: 0.07, green: 0.07, blue: 0.063)
        return Button { pick(look) } label: {
            VStack(spacing: 10) {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: atelier ? 8 : 11, style: .continuous).fill(hero)
                            .overlay(alignment: .leading) {
                                HStack(spacing: 6) {
                                    Circle().trim(from: 0, to: 0.7).stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                        .rotationEffect(.degrees(-90)).frame(width: 28, height: 28)
                                    Text(verbatim: "46").font(.system(size: 24, weight: .semibold, design: atelier ? .serif : .default))
                                        .foregroundStyle(.white)
                                }
                                .padding(.leading, 10)
                            }
                    }
                    .frame(height: 64)
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: atelier ? 8 : 11, style: .continuous).fill(.white)
                            .overlay(alignment: .bottom) {
                                HStack(alignment: .bottom, spacing: 3) {
                                    ForEach([0.4, 0.7, 0.5, 0.9, 0.6], id: \.self) { h in
                                        Capsule().fill(h == 0.6 ? accent : Color.black.opacity(0.08)).frame(width: 6, height: 30 * h)
                                    }
                                }
                                .padding(.bottom, 8)
                            }
                            .overlay(RoundedRectangle(cornerRadius: atelier ? 8 : 11, style: .continuous).strokeBorder(Color.black.opacity(atelier ? 0.08 : 0)))
                        RoundedRectangle(cornerRadius: atelier ? 8 : 11, style: .continuous).fill(accent.opacity(0.14))
                            .overlay(Image(systemName: "infinity").font(.headline).foregroundStyle(accent))
                    }
                    .frame(height: 52)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(bg))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.1)))
                look.title.font(.system(.headline, design: atelier ? .serif : .default))
                Text(store.hasPlus || !ThemeTrial.available ? LocalizedStringKey("Use it") : LocalizedStringKey("Try it free"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Capsule().fill(accent))
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func pick(_ look: DFLook) {
        guard ThemeTrial.canUse(look, hasPlus: store.hasPlus) else { showPlus = true; return }
        if !store.hasPlus { ThemeTrial.begin() }
        lookRaw = look.rawValue
        dismiss()
    }
}
