import SwiftUI
import UIKit

/// Le premier lancement : ajouter le clavier, étalonner la prise en main, puis l'essai gratuit.
/// Tout reste modifiable ensuite (accueil → Étalonner ma prise en main).
struct OnboardingView: View {
    var onDone: () -> Void
    @Environment(Store.self) private var store
    @Environment(SettingsModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var page: Int

    init(start: Int = 0, onDone: @escaping () -> Void) {
        self.onDone = onDone
        _page = State(initialValue: start)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ForEach(0..<5) { i in
                    Capsule().fill(i <= page ? Color.accentColor : Color(.systemFill)).frame(height: 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Group {
                switch page {
                case 0: welcome
                case 1: addKeyboard
                case 2:
                    VStack(spacing: 0) {
                        PlaceTutorial(onFinish: { page = 3 })
                        Button("Skip for now") { page = 3 }.font(.subheadline).padding(.bottom, 6)
                    }
                case 3:
                    KeyboardTour { page = 4 }
                default: trial
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: page)
        }
        .interactiveDismissDisabled()
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Spacer()
            Image("Logo").resizable().frame(width: 96, height: 96).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            Text("Welcome to Foldboard").font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text("The keyboard comes out under the thumb of the hand holding your phone. On the open Duo, it splits in two.")
                .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("1 minute to set it up.").font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            next("Get started") { page = 1 }
        }
        .padding(24)
    }

    private var addKeyboard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add the keyboard").font(.largeTitle.bold())
            step(1, "Tap **Open Settings** below.")
            step(2, "Tap **Keyboards**, turn on **Foldboard**, then **Allow Full Access**.")
            step(3, "Come back here.")
            Label("Full Access is only used for vibrations, typing sounds and to share your settings between the app and the keyboard. Nothing you type is sent anywhere.", systemImage: "lock.shield")
                .font(.footnote).foregroundStyle(.secondary)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Label("Open Settings", systemImage: "gear").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            Spacer()
            next("Next") {
                UserDefaults.standard.set(true, forKey: "setupDone")
                page = 2
            }
        }
        .padding(24)
    }

    /// Apprendre les pouces, façon Face ID (on peut le passer et le faire plus tard).
    private var thumbs: some View {
        VStack(spacing: 0) {
            GripSetup(onFinish: { finishThumbs() })
            Button("Skip for now") { finishThumbs() }
                .font(.subheadline)
                .padding(.bottom, 6)
        }
    }

    private func finishThumbs() {
        var s = model.settings
        s.mode = .auto
        model.settings = s
        page = 3
    }

    private var calibrate: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("How do you hold it?").font(.largeTitle.bold())
                Text("Hold the phone as you usually type, then tap the matching button. Do it closed and open: the angles are not the same.")
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            List { TiltCalibration() }
                .scrollContentBackground(.hidden)
            VStack(spacing: 8) {
                next(calibrated ? "Next" : "Skip for now") {
                    var s = model.settings
                    s.mode = .auto
                    model.settings = s
                    page = 3
                }
                Text("You can change it later from the home screen.").font(.footnote).foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }

    /// Le clavier à ton goût dès le début : disposition, hauteur, largeur, écart avec le bord (avec l'aperçu).
    private var yourKeyboard: some View {
        @Bindable var m = model
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your keyboard").font(.largeTitle.bold())
                Text("Set it to your thumb. You can try it right below.").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            List {
                Picker("Layout", selection: $m.settings.layout) {
                    ForEach(KBLayout.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                slider("Key height", value: $m.settings.keyHeight, in: 34...60, format: { "\(Int($0)) pt" })
                slider("One-hand width", value: $m.settings.oneHandWidth, in: 0.45...0.95, format: { "\(Int($0 * 100)) %" })
                slider("Distance from the edge", value: $m.settings.edgeMargin, in: 0...120, format: { "\(Int($0)) pt" })
                Toggle("Auto-correction", isOn: $m.settings.autocorrect)
            }
            .scrollContentBackground(.hidden)
            next("Next") { page = 4 }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
            PreviewDock(startClosed: true)
        }
    }

    private var calibrated: Bool {
        !model.settings.calib.isEmpty
    }

    private var trial: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "sparkles").font(.system(size: 48)).foregroundStyle(Color.accentColor)
            Text("Try everything free for 3 days").font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text("Two hands, follow-your-hand, colors, fonts, sounds and your phrases. Nothing renews, no subscription.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            if store.isPro {
                next("Start typing") { onDone() }
            } else {
                next("Start the 3-day free trial") {
                    Task {
                        await store.buy(KBProducts.trial)
                        if store.isPro { onDone() }
                    }
                }
                Button("Later") { onDone() }.padding(.top, 4)
            }
            if store.busy { ProgressView() }
            if let msg = store.message { Text(msg).font(.footnote).foregroundStyle(.red) }
        }
        .padding(24)
    }

    private func next(_ title: LocalizedStringKey, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.headline).foregroundStyle(.white)
                .frame(width: 28, height: 28).background(Circle().fill(Color.accentColor))
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// L'étalonnage, accessible à tout moment depuis l'accueil.
struct CalibrationScreen: View {
    var body: some View {
        List { TiltCalibration() }
            .navigationTitle("Calibrate my grip")
            .safeAreaInset(edge: .bottom, spacing: 0) { PreviewDock() }
    }
}
