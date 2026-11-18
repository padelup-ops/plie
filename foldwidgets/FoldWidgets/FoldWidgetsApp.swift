import SwiftUI

@main
struct FoldWidgetsApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @State private var settings = FoldStore.load()
    @State private var hardwareOpen: Double?
    @State private var manualOpen = 1.0
    @State private var message = ""
    @State private var busy = false
    @State private var share: SharePayload?

    private var openAmount: Double { hardwareOpen ?? manualOpen }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let wide = geo.size.width > geo.size.height + 40
                let gutter = geo.foldGutter()
                Group {
                    if wide {
                        HStack(spacing: gutter) {
                            preview(maxWidth: geo.size.width * 0.46, maxHeight: geo.size.height - 24)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            ScrollView { controls.padding(24) }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .padding(.horizontal, 20)
                    } else {
                        let cardHeight = min(geo.size.height * 0.46, 520)
                        ScrollView {
                            VStack(spacing: 24) {
                                preview(maxWidth: geo.size.width - 40, maxHeight: cardHeight)
                                controls
                            }
                            .padding(20)
                        }
                    }
                }
            }
            .background(Color(hex: 0x0E1014).ignoresSafeArea())
            .navigationTitle(Text("Fold Widgets"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(hex: 0x0E1014), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .tint(Color(hex: 0xE4C27A))
        .preferredColorScheme(.dark)
        .onHinge { closed, degrees in
            if let degrees {
                hardwareOpen = min(1, max(0, degrees / 180))
            } else if closed == true {
                hardwareOpen = 0
            } else if closed == false {
                hardwareOpen = 1
            } else {
                hardwareOpen = nil
            }
        }
        .onAppear {
            if !FoldStore.hasSaved {
                FoldStore.save(settings)
            }
        }
        .onChange(of: settings) { _, updated in
            FoldStore.save(updated)
        }
        .sheet(item: $share) { payload in
            ActivitySheet(items: payload.urls)
                .ignoresSafeArea()
        }
    }

    private func preview(maxWidth: CGFloat, maxHeight: CGFloat) -> some View {
        let ratio = 1398.0 / 2034.0
        let width = min(max(1, maxWidth), max(1, maxHeight) * ratio)
        let height = width / ratio
        let size = CGSize(width: width, height: height)
        return TimelineView(.periodic(from: .now, by: settings.theme == .hour ? 1 : 30)) { context in
            FoldArtwork(
                settings: settings,
                mode: .live,
                date: context.date,
                openAmount: openAmount,
                size: size
            )
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .accessibilityLabel(Text(NSLocalizedString(settings.theme.nameKey, comment: "")))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(NSLocalizedString(settings.theme.detailKey, comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FoldTheme.allCases) { theme in
                        Button {
                            settings.theme = theme
                        } label: {
                            Text(NSLocalizedString(theme.nameKey, comment: ""))
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(settings.theme == theme ? Color(hex: 0xE4C27A) : Color.white.opacity(0.08), in: Capsule())
                                .foregroundStyle(settings.theme == theme ? Color.black : Color.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            editor

            if hardwareOpen == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Opening")
                        .font(.subheadline.weight(.medium))
                    Slider(value: $manualOpen, in: 0...1)
                    Text("No hinge on this iPhone. Drag to preview the fold.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack {
                    Text("Live hinge")
                    Spacer()
                    Text("\(Int(openAmount * 180))°")
                        .monospacedDigit()
                        .foregroundStyle(Color(hex: 0xE4C27A))
                }
                .font(.subheadline)
            }

            Text("The pair saves the closed cover and the open inside.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Outer 1398 × 2034 · Inner 1878 × 2670 · Card 1080 × 1920")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    savePair()
                } label: {
                    Text("Save the pair")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy)

                Button {
                    shareCard()
                } label: {
                    Text("Share")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(busy)
            }

            if !message.isEmpty {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color(hex: 0xE4C27A))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Widgets follow the family, not the fold. Small is the cover, medium is two panes, large is the inside.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Nothing is collected. Wallpapers stay on this iPhone until you share them.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var editor: some View {
        switch settings.theme {
        case .revelation:
            labeled("Word") {
                TextField(text: $settings.revelationWord, prompt: Text(settings.prefersFrench ? "OUVERT" : "OPEN")) {
                    Text("Word")
                }
                .textInputAutocapitalization(.characters)
                .fieldChrome()
            }
        case .hour:
            EmptyView()
        case .quote:
            VStack(alignment: .leading, spacing: 10) {
                Text(settings.resolvedQuote.text(french: settings.prefersFrench))
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Previous quote") { stepQuote(-1) }
                    Button("Next quote") { stepQuote(1) }
                }
                .buttonStyle(.bordered)
                labeled("Your sentence") {
                    TextField(text: $settings.customQuote, prompt: Text("Your sentence")) {
                        Text("Your sentence")
                    }
                    .fieldChrome()
                }
                labeled("Signature") {
                    TextField(text: $settings.customAuthor, prompt: Text("Fold Widgets")) {
                        Text("Signature")
                    }
                    .fieldChrome()
                }
            }
        case .diptych:
            HStack(spacing: 12) {
                ForEach(DiptychPalette.allCases) { palette in
                    Button {
                        settings.diptychPalette = palette.rawValue
                    } label: {
                        Circle()
                            .fill(Ink.diptych[palette.rawValue].accent)
                            .frame(width: 36, height: 36)
                            .overlay(Circle().stroke(Color.white, lineWidth: settings.palette == palette ? 2 : 0))
                            .accessibilityLabel(Text(NSLocalizedString(palette.nameKey, comment: "")))
                    }
                    .buttonStyle(.plain)
                }
            }
        case .countdown:
            DatePicker("Date", selection: $settings.countdownDate, displayedComponents: [.date, .hourAndMinute])
            labeled("Title") {
                TextField(text: $settings.countdownTitle, prompt: Text("The day")) {
                    Text("Title")
                }
                .fieldChrome()
            }
        case .mood:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(Mood.allCases) { mood in
                    Button {
                        settings.mood = mood
                    } label: {
                        Text(NSLocalizedString(mood.nameKey, comment: ""))
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(settings.mood == mood ? Ink.moods[mood]?.accent ?? Color.white : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(settings.mood == mood ? Color.black : Color.white)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func labeled<V: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.medium))
            content()
        }
    }

    private func stepQuote(_ delta: Int) {
        let count = Quote.catalog.count
        settings.quoteIndex = (settings.quoteIndex + delta + count) % count
        settings.customQuote = ""
    }

    private func savePair() {
        busy = true
        message = ""
        let settings = settings
        let date = Date()
        guard let pair = Exporter.pair(settings: settings, at: date) else {
            message = String(localized: "Could not draw the wallpapers")
            busy = false
            return
        }
        Exporter.saveToPhotos([pair.outer, pair.inner]) { result in
            Task { @MainActor in
                switch result {
                case .saved:
                    message = String(localized: "Pair saved to Photos")
                case .denied:
                    message = String(localized: "Photo access is off")
                case .failed:
                    message = String(localized: "Could not save the photos")
                }
                busy = false
            }
        }
    }

    private func shareCard() {
        busy = true
        message = ""
        let settings = settings
        let date = Date()
        guard let pair = Exporter.pair(settings: settings, at: date),
              let card = Exporter.card(settings: settings, outer: pair.outer, inner: pair.inner) else {
            message = String(localized: "Could not draw the wallpapers")
            busy = false
            return
        }
        do {
            let urls = [
                try Exporter.writeTemporary(card, name: "FoldWidgets-card.png"),
                try Exporter.writeTemporary(pair.outer, name: "FoldWidgets-outer.png"),
                try Exporter.writeTemporary(pair.inner, name: "FoldWidgets-inner.png")
            ]
            share = SharePayload(urls: urls)
        } catch {
            message = String(localized: "Could not draw the wallpapers")
        }
        busy = false
    }
}

private extension View {
    func fieldChrome() -> some View {
        self
            .textFieldStyle(.plain)
            .padding(12)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
