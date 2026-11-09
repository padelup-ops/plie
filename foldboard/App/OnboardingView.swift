import SwiftUI
import UIKit

/// Le premier lancement : ajouter le clavier, étalonner la prise en main, puis l'essai gratuit.
/// Tout reste modifiable ensuite (accueil → Étalonner ma prise en main).
struct OnboardingView: View {
    var onDone: () -> Void
    @Environment(Store.self) private var store
    @Environment(SettingsModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ForEach(0..<4) { i in
                    Capsule().fill(i <= page ? Color.accentColor : Color(.systemFill)).frame(height: 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Group {
                switch page {
                case 0: welcome
                case 1: addKeyboard
                case 2: calibrate
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
            Text("The keyboard that comes to the hand holding your phone, and splits in two when you use both hands.")
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

    private var calibrate: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("How do you hold it?").font(.largeTitle.bold())
                Text("Hold the phone as you usually type, then tap the matching button. Do it for each hand, and with both hands.")
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

    private var calibrated: Bool {
        !model.settings.postureRight.isEmpty && !model.settings.postureLeft.isEmpty
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
