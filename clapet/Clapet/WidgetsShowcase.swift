import SwiftUI
import UIKit
import WidgetKit

// MARK: - Les widgets, mis en avant dans l'app
//
// Une carte sur l'accueil tant qu'aucun widget n'est installé (avec un aperçu des vrais widgets,
// aux vrais chiffres), et la galerie : écran d'accueil, écran verrouillé, couleur, comment les ajouter.

/// Combien de widgets Foldly sont installés (écran d'accueil et écran verrouillé).
@Observable
final class InstalledWidgets {
    static let shared = InstalledWidgets()

    /// nil : pas encore lu.
    private(set) var count: Int?

    func refresh() {
        WidgetCenter.shared.getCurrentConfigurations { result in
            let n = (try? result.get())?.count ?? 0
            DispatchQueue.main.async { self.count = n }
        }
    }
}

/// Un widget dessiné dans l'app, à sa vraie taille (ou réduit).
struct WidgetThumb: View {
    enum Kind { case folds, phoneDown }

    let kind: Kind
    let family: WidgetFamily
    let entry: ClapetEntry
    var scale: CGFloat = 1

    static func size(_ family: WidgetFamily) -> CGSize {
        switch family {
        case .systemMedium: return CGSize(width: 338, height: 158)
        case .systemLarge: return CGSize(width: 338, height: 354)
        case .accessoryCircular: return CGSize(width: 72, height: 72)
        case .accessoryRectangular: return CGSize(width: 170, height: 72)
        case .accessoryInline: return CGSize(width: 240, height: 24)
        default: return CGSize(width: 158, height: 158)
        }
    }

    private var isAccessory: Bool {
        family == .accessoryCircular || family == .accessoryRectangular || family == .accessoryInline
    }

    var body: some View {
        let size = Self.size(family)
        Group {
            switch kind {
            case .folds: ClapetWidgetView(entry: entry, family: family)
            case .phoneDown: PhoneDownWidgetView(entry: entry, family: family)
            }
        }
        .padding(isAccessory ? 0 : 16)
        .frame(width: size.width, height: size.height)
        .background {
            if !isAccessory {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Palette.background)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: isAccessory ? 0 : 24, style: .continuous))
        .environment(\.colorScheme, .dark)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
        .shadow(color: .black.opacity(isAccessory ? 0 : 0.18), radius: 10, y: 4)
        .accessibilityHidden(true)
    }
}

/// Un faux écran verrouillé, avec les widgets de Foldly dessus.
struct LockScreenMock: View {
    let entry: ClapetEntry
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 4 : 8) {
            WidgetThumb(kind: .phoneDown, family: .accessoryInline, entry: entry, scale: compact ? 0.8 : 1)
                .foregroundStyle(.white)
            Text(entry.date, format: .dateTime.hour().minute())
                .font(.system(size: compact ? 44 : 76, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
            HStack(spacing: compact ? 6 : 10) {
                WidgetThumb(kind: .folds, family: .accessoryCircular, entry: entry, scale: compact ? 0.72 : 1)
                WidgetThumb(kind: .phoneDown, family: .accessoryRectangular, entry: entry, scale: compact ? 0.72 : 1)
                if !compact {
                    WidgetThumb(kind: .phoneDown, family: .accessoryCircular, entry: entry)
                }
            }
            .foregroundStyle(.white)
        }
        .padding(.vertical, compact ? 14 : 24)
        .padding(.horizontal, compact ? 12 : 16)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Color(red: 0.16, green: 0.20, blue: 0.42), Color(red: 0.42, green: 0.22, blue: 0.48),
                                    Color(red: 0.93, green: 0.52, blue: 0.46)],
                           startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: compact ? 20 : 28, style: .continuous))
        .environment(\.colorScheme, .dark)
        .accessibilityHidden(true)
    }
}

/// Réduit un aperçu pour qu'il tienne dans la largeur disponible (écran extérieur compris).
struct FitWidth<Content: View>: View {
    let size: CGSize
    @ViewBuilder var content: (CGFloat) -> Content

    var body: some View {
        GeometryReader { g in
            content(min(1, g.size.width / size.width))
        }
        .aspectRatio(size.width / size.height, contentMode: .fit)
        .frame(maxWidth: size.width)
    }
}

/// La carte de l'accueil : « Foldly sur ton écran d'accueil ».
struct WidgetsPromo: View {
    @Environment(ClapetModel.self) private var model
    var onOpen: () -> Void
    var onHide: () -> Void

    var body: some View {
        let entry = ClapetEntry(date: Date(), stats: model.stats)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Put Foldly on your Home Screen")
                        .font(.headline)
                    Text("Your folds and your time open and closed at a glance, without opening the app.")
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    WidgetThumb(kind: .folds, family: .systemSmall, entry: entry, scale: 0.82)
                    WidgetThumb(kind: .phoneDown, family: .systemSmall, entry: entry, scale: 0.82)
                    LockScreenMock(entry: entry, compact: true)
                        .frame(width: 204)
                }
                .padding(.vertical, 6)
            }
            .scrollClipDisabled()
            Button(action: onOpen) {
                Label { Text("Add a widget") } icon: { Image(systemName: "plus.square.on.square") }
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

/// La carte est montrée tant qu'aucun widget n'est installé, sauf si on l'a écartée (elle revient 2 semaines plus tard).
enum WidgetsPromoRule {
    private static let key = "widgetsPromoHiddenUntil"

    static func shouldShow(installed: Int?) -> Bool {
        guard installed == 0, !Demo.seeded else { return false }
        let until = UserDefaults.standard.double(forKey: key)
        return Date().timeIntervalSince1970 >= until
    }

    static func hide() {
        UserDefaults.standard.set(Date().addingTimeInterval(14 * 86_400).timeIntervalSince1970, forKey: key)
    }
}

/// Le sous-titre de la ligne « Widgets » des menus.
func widgetsDetail(_ installed: Int?) -> Text {
    guard let installed, installed > 0 else { return Text("Home Screen and Lock Screen") }
    return installed == 1 ? Text("1 widget on your screens") : Text("\(installed) widgets on your screens")
}

/// La galerie des widgets : à quoi ils ressemblent, leur couleur, et comment les ajouter.
struct WidgetsHelpView: View {
    @Environment(ClapetModel.self) private var model
    @Environment(ClapetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var installed = InstalledWidgets.shared
    @State private var place: Place = .home
    @State private var showPlus = false

    enum Place: Hashable { case home, lock }

    var body: some View {
        let entry = ClapetEntry(date: Date(), stats: model.stats)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Picker(selection: $place) {
                        Text("Home Screen").tag(Place.home)
                        Text("Lock Screen").tag(Place.lock)
                    } label: {
                        Text("Widgets")
                    }
                    .pickerStyle(.segmented)

                    if place == .home {
                        section(Text("Folds today"), Text("Your folds, compared with your average, and your week."), symbol: "rectangle.compress.vertical") {
                            WidgetThumb(kind: .folds, family: .systemSmall, entry: entry)
                            FitWidth(size: WidgetThumb.size(.systemMedium)) { k in
                                WidgetThumb(kind: .folds, family: .systemMedium, entry: entry, scale: k)
                            }
                            FitWidth(size: WidgetThumb.size(.systemLarge)) { k in
                                WidgetThumb(kind: .folds, family: .systemLarge, entry: entry, scale: k)
                            }
                        }
                        section(Text("Open & closed"), Text("How long your phone stayed open and closed today."), symbol: "moon.zzz.fill") {
                            WidgetThumb(kind: .phoneDown, family: .systemSmall, entry: entry)
                            FitWidth(size: WidgetThumb.size(.systemMedium)) { k in
                                WidgetThumb(kind: .phoneDown, family: .systemMedium, entry: entry, scale: k)
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            LockScreenMock(entry: entry)
                            Text("They show on the outer screen too, when your phone is closed: a timer shows how long it has been closed.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    colors
                    steps
                    if let n = installed.count, n > 0 {
                        Label { widgetsDetail(n) } icon: { Image(systemName: "checkmark.circle.fill") }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.dfAccent)
                    }
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Color.dfBackground.ignoresSafeArea())
            .navigationTitle(Text("Widgets"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done") }
                }
            }
        }
        .tint(.dfAccent)
        .onAppear { installed.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in installed.refresh() }
        .sheet(isPresented: $showPlus) {
            PlusView(reason: PlusReason.widget.text).environment(model).environment(store)
        }
    }

    private func section<Content: View>(_ title: Text, _ detail: Text, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Label { title } icon: { Image(systemName: symbol).foregroundStyle(Color.dfAccent) }
                    .font(.title3.weight(.semibold))
                detail
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
    }

    /// La couleur des widgets, avec l'aperçu qui change tout de suite.
    private var colors: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Widget color")
                .font(.headline)
            HStack(spacing: 12) {
                ForEach(ClapetTheme.allCases) { theme in
                    Button {
                        if store.hasPlus || theme == .mint {
                            withAnimation(.easeInOut(duration: 0.2)) { model.setTheme(theme) }
                        } else {
                            showPlus = true
                        }
                    } label: {
                        Circle()
                            .fill(theme.color)
                            .frame(width: 36, height: 36)
                            .overlay(Circle().stroke(Color.primary, lineWidth: model.stats.theme == theme.rawValue ? 3 : 0).padding(-4))
                            .overlay {
                                if !store.hasPlus && theme != .mint {
                                    Image(systemName: "lock.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(.black.opacity(0.6))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(theme.name))
                    .accessibilityAddTraits(model.stats.theme == theme.rawValue ? .isSelected : [])
                }
            }
            .padding(.leading, 4)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How to add them")
                .font(.headline)
            if place == .home {
                step(1, Text("Touch and hold an empty spot on your Home Screen."))
                step(2, Text("Tap Edit, then Add Widget."))
                step(3, Text("Search for Foldly and pick a size."))
            } else {
                step(1, Text("Touch and hold your Lock Screen, then tap Customize."))
                step(2, Text("Tap Lock Screen, then the area under the clock."))
                step(3, Text("Pick Foldly: Folds today or Open & closed."))
            }
        }
    }

    private func step(_ n: Int, _ text: Text) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: "\(n)")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Color.dfOnAccent)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.dfAccent))
                .accessibilityHidden(true)
            text
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
        }
    }
}
