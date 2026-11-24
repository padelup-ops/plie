// CallViews.swift — Allô Père Noël
//
// Le moment magique : l'attente (le temps de donner l'iPhone), l'appel entrant (sonnerie douce, vibration,
// le bouton « Répondre » qui pulse), l'éclat doré au décroché, l'appel dans l'atelier avec ses sous-titres,
// la surprise de l'étoile, puis la fin qui s'assombrit et laisse place aux étoiles.

import SwiftUI

// MARK: - Attente

struct WaitingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.05, blue: 0.11).ignoresSafeArea()
            Snowfall(count: 30, opacity: 0.35)
            VStack(spacing: 18) {
                Spacer()
                TimelineView(.periodic(from: .now, by: 0.25)) { tl in
                    let left = max(0, Int(ceil((model.ringAt ?? tl.date).timeIntervalSince(tl.date))))
                    Text("\(left)")
                        .font(.tale(110))
                        .foregroundStyle(Noel.goldGradient)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy, value: left)
                        .monospacedDigit()
                }
                Text("Santa is about to call…")
                    .font(.tale(26))
                    .foregroundStyle(Noel.cream)
                Text("Hand the iPhone to your child and turn the volume up.")
                    .font(.ui(16))
                    .foregroundStyle(Noel.cream.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                Spacer()
                Button { model.home() } label: { Text("Cancel the call") }
                    .buttonStyle(QuietButtonStyle())
                    .padding(.horizontal, 60)
                    .padding(.bottom, 18)
            }
        }
        .task {
            while let at = model.ringAt, !Task.isCancelled {
                if Date() >= at { model.ring(); return }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }
}

// MARK: - Appel entrant

struct IncomingCallView: View {
    @Environment(AppModel.self) private var model
    @State private var pulse = false
    @State private var flash = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        ZStack {
            NightScene(moon: false, trees: true)
                .blur(radius: 14)
                .overlay(Color.black.opacity(0.38))
            RadialGradient(colors: [Noel.gold.opacity(pulse ? 0.36 : 0.18), .clear], center: .init(x: 0.5, y: 0.32), startRadius: 10, endRadius: 330)
                .ignoresSafeArea()
            Snowfall(count: 70)

            VStack(spacing: 0) {
                Text("INCOMING CALL")
                    .font(.ui(14, .semibold))
                    .tracking(3)
                    .foregroundStyle(Noel.cream.opacity(0.75))
                    .padding(.top, 40)

                ZStack {
                    ForEach(0..<3) { i in
                        Circle()
                            .strokeBorder(Noel.goldLight.opacity(0.5), lineWidth: 1.5)
                            .frame(width: 176, height: 176)
                            .scaleEffect(pulse ? 1.55 + Double(i) * 0.18 : 1)
                            .opacity(pulse ? 0 : 0.7)
                            .animation(reduce ? nil : .easeOut(duration: 2.2).repeatForever(autoreverses: false).delay(Double(i) * 0.5), value: pulse)
                    }
                    SantaMedallion(size: 176, mood: .idle)
                }
                .padding(.top, 44)

                Text("Santa Claus")
                    .font(.tale(42))
                    .foregroundStyle(Noel.cream)
                    .padding(.top, 34)
                Text("The North Pole is calling…")
                    .font(.story(21))
                    .foregroundStyle(Noel.goldLight)
                    .padding(.top, 6)

                Spacer()

                HStack {
                    callButton(symbol: "phone.down.fill", color: Color(red: 0.92, green: 0.26, blue: 0.24), label: "Decline") {
                        model.decline()
                    }
                    Spacer()
                    callButton(symbol: "phone.fill", color: Color(red: 0.20, green: 0.78, blue: 0.35), label: "Answer", pulsing: true) {
                        withAnimation(.easeIn(duration: 0.38)) { flash = true }
                        Task {
                            try? await Task.sleep(for: .milliseconds(380))
                            model.answer()
                        }
                    }
                }
                .padding(.horizontal, 54)
                .padding(.bottom, 44)
            }

            // L'éclat doré au décroché
            RadialGradient(colors: [Color.white, Noel.goldLight, Noel.gold.opacity(0)], center: .init(x: 0.78, y: 0.86),
                           startRadius: 0, endRadius: flash ? 1400 : 1)
                .opacity(flash ? 1 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .onAppear { pulse = true }
    }

    private func callButton(symbol: String, color: Color, label: LocalizedStringKey, pulsing: Bool = false, action: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 80, height: 80)
                    .background(Circle().fill(color))
                    .shadow(color: color.opacity(pulsing ? 0.75 : 0.3), radius: pulsing && pulse ? 24 : 8)
                    .scaleEffect(pulsing && pulse && !reduce ? 1.09 : 1)
                    .animation(pulsing && !reduce ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : nil, value: pulse)
            }
            .accessibilityLabel(Text(label))
            Text(label)
                .font(.ui(15, .medium))
                .foregroundStyle(Noel.cream)
        }
    }
}

// MARK: - L'appel

struct CallView: View {
    @Environment(AppModel.self) private var model
    @State private var entered = false

    var body: some View {
        let call = model.call
        ZStack {
            WorkshopScene()
            Snowfall(count: 22, speed: 0.5, opacity: 0.35)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                SantaView(mouth: call.mouth, mood: call.mood)
                    .frame(maxWidth: 460)
                    .scaleEffect(entered ? 1 : 0.9, anchor: .bottom)
                    .offset(y: 20)
            }
            .ignoresSafeArea(edges: .bottom)

            if let at = call.surpriseAt {
                SurpriseStar(start: at).id(at)
            }

            VStack(spacing: 12) {
                topBar
                if call.mood == .listening {
                    ListeningBubble().transition(.scale.combined(with: .opacity))
                }
                Spacer()
                if model.subtitles && !call.caption.isEmpty {
                    Text(call.caption)
                        .font(.story(22))
                        .foregroundStyle(Noel.cream)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 20).padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black.opacity(0.55)))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Noel.gold.opacity(0.3), lineWidth: 1))
                        .padding(.horizontal, 16)
                        .id(call.caption)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                }
                Button { model.hangUp() } label: {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 66, height: 66)
                        .background(Circle().fill(Color(red: 0.92, green: 0.26, blue: 0.24)))
                }
                .accessibilityLabel(Text("Hang up"))
                .padding(.bottom, 8)
            }
            .animation(.easeInOut(duration: 0.35), value: call.caption)
            .animation(.spring(duration: 0.4), value: call.mood)

            // l'éclat du décroché qui se dissipe
            RadialGradient(colors: [Color.white, Noel.goldLight, Noel.gold.opacity(0)], center: .center, startRadius: 0, endRadius: 1400)
                .opacity(entered ? 0 : 1)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .onAppear {
            if ShotMode.route != nil { entered = true; return }
            withAnimation(.easeOut(duration: 1.1)) { entered = true }
        }
    }

    private var topBar: some View {
        @Bindable var model = model
        return HStack {
            HStack(spacing: 8) {
                Circle().fill(Color(red: 0.3, green: 0.85, blue: 0.4)).frame(width: 8, height: 8)
                Text("Santa Claus").font(.ui(15, .semibold))
                TimelineView(.periodic(from: .now, by: 1)) { tl in
                    let s = max(0, Int(tl.date.timeIntervalSince(model.call.startedAt ?? tl.date)))
                    Text(String(format: "%d:%02d", s / 60, s % 60)).font(.ui(15)).monospacedDigit().opacity(0.75)
                }
            }
            .foregroundStyle(Noel.cream)
            .padding(.horizontal, 14).frame(height: 40)
            .background(Capsule().fill(Color.black.opacity(0.4)))
            Spacer()
            Button { model.subtitles.toggle() } label: {
                Image(systemName: model.subtitles ? "captions.bubble.fill" : "captions.bubble")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Noel.cream)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.black.opacity(0.4)))
            }
            .accessibilityLabel(Text(model.subtitles ? "Hide subtitles" : "Show subtitles"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }
}

/// Pendant les pauses : le Père Noël écoute la réponse de l'enfant (rien n'est enregistré).
struct ListeningBubble: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "ear.fill")
            Text("Santa is listening…")
            Image(systemName: "ellipsis").symbolEffect(.variableColor.iterative, options: .repeating)
        }
        .font(.ui(15, .semibold))
        .foregroundStyle(Noel.night)
        .padding(.horizontal, 16).frame(height: 38)
        .background(Capsule().fill(Noel.goldGradient))
        .shadow(color: Noel.gold.opacity(0.5), radius: 12)
    }
}

/// La surprise : une grande étoile dorée qui apparaît, et une pluie d'étoiles.
struct SurpriseStar: View {
    var start: Date

    var body: some View {
        ZStack {
            GeometryReader { geo in
                TimelineView(.animation(minimumInterval: Motion.interval)) { tl in
                    let t = tl.date.timeIntervalSince(start)
                    let grow = min(1, max(0, t / 0.6))
                    let fade = t < 3.4 ? 1 : max(0, 1 - (t - 3.4) / 0.8)
                    ZStack {
                        Circle().fill(RadialGradient(colors: [Noel.goldLight.opacity(0.7), .clear], center: .center, startRadius: 10, endRadius: 170))
                            .frame(width: 340, height: 340)
                        StarShape().fill(Noel.goldGradient)
                            .frame(width: 130, height: 130)
                            .shadow(color: Noel.goldLight, radius: 26)
                            .rotationEffect(.degrees(t * 18))
                    }
                    .scaleEffect(0.2 + 0.8 * (1 - pow(1 - grow, 3)))
                    .opacity(fade)
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.36)
                }
            }
            StarBurst(start: start, count: 46)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Fin de l'appel

struct EndView: View {
    @Environment(AppModel.self) private var model
    @Environment(MagicStore.self) private var store
    @State private var shown = false
    @State private var burst = Date()

    var body: some View {
        ZStack {
            NightScene(moon: false, trees: false)
            Color.black.opacity(shown ? 0.25 : 0.9).ignoresSafeArea()
            StarBurst(start: burst, count: 50)
            VStack(spacing: 0) {
                Spacer()
                StarShape().fill(Noel.goldGradient)
                    .frame(width: 54, height: 54)
                    .shadow(color: Noel.goldLight, radius: 18)
                    .scaleEffect(shown ? 1 : 0.3)
                Text("Santa sent you a little magic.")
                    .font(.tale(34))
                    .foregroundStyle(Noel.cream)
                    .multilineTextAlignment(.center)
                    .padding(.top, 26)
                    .padding(.horizontal, 30)
                    .opacity(shown ? 1 : 0)
                Spacer()
                VStack(spacing: 12) {
                    Button { model.replay(premium: store.owned) } label: { Label("Replay the call", systemImage: "arrow.counterclockwise") }
                        .buttonStyle(MagicButtonStyle())
                    Button { model.sheet = .memory } label: { Label("Create a keepsake", systemImage: "photo.on.rectangle.angled") }
                        .buttonStyle(QuietButtonStyle())
                    Button { model.home() } label: {
                        Text("Back to home").font(.ui(16, .semibold)).foregroundStyle(Noel.cream.opacity(0.75)).padding(10)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
                .opacity(shown ? 1 : 0)
            }
        }
        .onAppear {
            burst = Date().addingTimeInterval(ShotMode.route != nil ? -0.5 : 0.4)
            withAnimation(.easeOut(duration: ShotMode.route != nil ? 0 : 1.6)) { shown = true }
        }
    }
}

/// L'enfant a refusé l'appel : le parent peut le relancer quand il veut (jamais automatiquement).
struct DeclinedView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            NightScene()
            Snowfall(count: 50)
            VStack(spacing: 18) {
                Spacer()
                SantaMedallion(size: 150)
                Text("Santa will call back in a moment.")
                    .font(.tale(28))
                    .foregroundStyle(Noel.cream)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                Spacer()
                VStack(spacing: 12) {
                    Button { model.ring() } label: { Label("Call back now", systemImage: "phone.fill") }
                        .buttonStyle(MagicButtonStyle())
                    Button { model.home() } label: { Text("Back to home") }
                        .buttonStyle(QuietButtonStyle(filled: true))
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 14)
            }
        }
    }
}
