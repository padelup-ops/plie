// HomeView.swift — Allô Père Noël
//
// Le lancement (le titre qui apparaît dans la nuit) et l'accueil : la nuit du pôle Nord, la lune, la neige,
// le Père Noël dans son médaillon doré, le compte à rebours, et un seul geste principal : préparer l'appel.

import SwiftUI
import UIKit

struct SplashView: View {
    @Environment(AppModel.self) private var model
    @State private var shown = false

    var body: some View {
        ZStack {
            NightScene(trees: true)
            Snowfall(count: 70)
            VStack(spacing: 6) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Noel.goldGradient)
                    .rotationEffect(.degrees(-18))
                    .padding(.bottom, 8)
                Text("Allô")
                    .font(.story(34))
                    .foregroundStyle(Noel.goldLight)
                Text("Père Noël")
                    .font(.tale(54))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .padding(.horizontal, 24)
                    .foregroundStyle(Noel.cream)
                    .shadow(color: Noel.goldLight.opacity(0.5), radius: 18)
            }
            .offset(y: -60)
            .scaleEffect(shown ? 1 : 0.92)
            .opacity(shown ? 1 : 0)
            .blur(radius: shown ? 0 : 6)
        }
        .task {
            withAnimation(.easeOut(duration: 0.9)) { shown = true }
            try? await Task.sleep(for: .milliseconds(1700))
            model.go(.home)
        }
        .accessibilityElement(children: .combine)
    }
}

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(MagicStore.self) private var store
    @State private var appeared = false
    @State private var music = ChristmasMusic.shared
    @State private var greeting: Task<Void, Never>?
    private static var greeted = false

    var body: some View {
        ZStack {
            NightScene()
            Snowfall()
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    CountdownChip()
                    Spacer()
                    Button { music.enabled.toggle() } label: {
                        RoundIcon(symbol: music.enabled ? "music.note" : "speaker.slash.fill")
                    }
                    .accessibilityLabel(Text(music.enabled ? "Turn the music off" : "Turn the music on"))
                    Button { model.sheet = .settings } label: { RoundIcon(symbol: "gearshape.fill") }
                        .accessibilityLabel(Text("Settings"))
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer(minLength: 12)
                // Le Père Noël, en photo : un toucher et il dit bonjour.
                Button { greet(again: true) } label: {
                    SantaMedallion(size: 214, mood: model.call.previewing ? model.call.mood : .idle,
                                   mouth: model.call.previewing ? model.call.mouth : 0)
                        .scaleEffect(appeared ? 1 : 0.94)
                        .opacity(appeared ? 1 : 0)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Hear Santa's greeting"))
                Spacer(minLength: 18)

                VStack(spacing: 12) {
                    Text("Santa has a message for you…")
                        .font(.tale(34))
                        .foregroundStyle(Noel.cream)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
                    Text("Prepare a magical moment your child will never forget.")
                        .font(.ui(17))
                        .foregroundStyle(Noel.cream.opacity(0.82))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
                .padding(.horizontal, 24)
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 24)

                VStack(spacing: 12) {
                    Button { model.go(.setup) } label: { Text("✨ Prepare a magic call") }
                        .buttonStyle(MagicButtonStyle())
                    HStack(spacing: 10) {
                        Button { model.sheet = .advent } label: { Text("Advent calendar").lineLimit(1).minimumScaleFactor(0.7) }
                            .buttonStyle(QuietButtonStyle(filled: true))
                        if !store.owned {
                            Button { model.sheet = .paywall } label: { Text("Christmas Pass").lineLimit(1).minimumScaleFactor(0.7) }
                                .buttonStyle(QuietButtonStyle(filled: true))
                        }
                    }
                    Button { model.sheet = .discover } label: {
                        Text("Discover the magic").font(.ui(16, .semibold)).foregroundStyle(Noel.night.opacity(0.75)).padding(.vertical, 4)
                    }
                    Text("A magical moment to share as a family")
                        .font(.story(15))
                        .foregroundStyle(Noel.night.opacity(0.62))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 14)
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.9)) { appeared = true }
            greet(again: false)
        }
        .onDisappear {
            greeting?.cancel()
            model.call.stopSolo()
            music.duck(false)
        }
    }

    /// Le Père Noël dit bonjour, de sa vraie voix : une fois au lancement, puis à chaque toucher du médaillon.
    private func greet(again: Bool) {
        guard ShotMode.route == nil, !model.call.previewing else { return }
        if !again && Self.greeted { return }
        Self.greeted = true
        greeting?.cancel()
        greeting = Task {
            try? await Task.sleep(for: .milliseconds(again ? 0 : 700))
            guard !Task.isCancelled, model.screen == .home, model.sheet == nil else { return }
            music.duck(true)
            await model.call.speakBlock("welcome")
            music.duck(false)
        }
    }
}

/// « Plus que 30 jours avant Noël 🎄 », avec une petite étoile qui scintille.
struct CountdownChip: View {
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "sparkle")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Noel.goldLight)
                .symbolEffect(.pulse, options: .repeating)
            Text(Countdown.text)
                .font(.ui(14, .semibold))
                .foregroundStyle(Noel.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Capsule().fill(Noel.night.opacity(0.55)))
        .overlay(Capsule().strokeBorder(Noel.gold.opacity(0.45), lineWidth: 1))
    }
}
