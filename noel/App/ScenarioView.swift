// ScenarioView.swift — Allô Père Noël
//
// Le choix de l'histoire : cinq scénarios, tous visibles, le premier gratuit. Puis le moment où le téléphone
// doit sonner (tout de suite, ou après quelques secondes pour avoir le temps de le donner à l'enfant).

import SwiftUI

struct ScenarioView: View {
    @Environment(AppModel.self) private var model
    @Environment(MagicStore.self) private var store

    var body: some View {
        @Bindable var model = model
        ZStack {
            NightScene(moon: false, trees: false)
            Snowfall(count: 36, opacity: 0.5)
            VStack(spacing: 0) {
                HStack {
                    Button { model.go(.setup) } label: { RoundIcon(symbol: "chevron.left") }
                        .accessibilityLabel(Text("Back"))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Choose the story")
                                .font(.tale(32))
                                .foregroundStyle(Noel.cream)
                            Text("for \(model.profile.cleanNames.formatted(.list(type: .and)))")
                                .font(.story(19))
                                .foregroundStyle(Noel.goldLight)
                        }
                        .padding(.bottom, 6)

                        ForEach(Scenario.allCases) { s in
                            ScenarioCard(scenario: s, selected: model.scenario == s, locked: !s.isFree && !store.owned) {
                                withAnimation(.spring(duration: 0.35, bounce: 0.3)) { model.scenario = s }
                            }
                        }

                        Text("When should Santa call?")
                            .font(.story(19))
                            .foregroundStyle(Noel.cream)
                            .padding(.top, 14)
                        HStack(spacing: 8) {
                            ForEach(RingDelay.allCases) { d in
                                let on = model.delay == d
                                Button { withAnimation(.snappy) { model.delay = d } } label: {
                                    Text(d.label)
                                        .font(.ui(15, .semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                        .foregroundStyle(on ? Noel.night : Noel.cream)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 42)
                                        .background(Capsule().fill(on ? AnyShapeStyle(Noel.goldGradient) : AnyShapeStyle(Noel.night.opacity(0.55))))
                                        .overlay(Capsule().strokeBorder(Noel.cream.opacity(on ? 0 : 0.2), lineWidth: 1))
                                }
                                .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "speaker.wave.2.fill")
                            Text("When it rings, hand the iPhone to your child. Turn the volume up!")
                        }
                        .font(.ui(14))
                        .foregroundStyle(Noel.cream.opacity(0.7))
                        .padding(.top, 2)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                }

                // Comme en appel vidéo : le parent décide ici, avant l'appel, si son enfant se voit dans un coin.
                ReactionOptions()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)

                Button {
                    if !model.scenario.isFree && !store.owned {
                        model.sheet = .paywall
                    } else {
                        model.startCall(premium: store.owned)
                    }
                } label: {
                    Label {
                        Text(!model.scenario.isFree && !store.owned ? "Unlock this story" : "Start the call")
                    } icon: {
                        Image(systemName: !model.scenario.isFree && !store.owned ? "lock.open.fill" : "phone.fill")
                    }
                }
                .buttonStyle(MagicButtonStyle())
                .padding(.horizontal, 28)
                .padding(.bottom, model.scenario.isFree && !store.owned ? 4 : 10)
                if model.scenario.isFree && !store.owned {
                    Text("A short free preview")
                        .font(.ui(13))
                        .foregroundStyle(Noel.cream.opacity(0.6))
                        .padding(.bottom, 10)
                }
            }
        }
    }
}

struct ScenarioCard: View {
    var scenario: Scenario
    var selected: Bool
    var locked: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [scenario.tint.opacity(0.95), scenario.tint.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                    Circle().strokeBorder(Noel.goldGradient, lineWidth: selected ? 2.5 : 1)
                    Image(systemName: scenario.symbol)
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(Noel.cream)
                        .symbolEffect(.bounce, value: selected)
                }
                .frame(width: 60, height: 60)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(scenario.title)
                            .font(.tale(20))
                            .foregroundStyle(Noel.cream)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    Text(scenario.blurb)
                        .font(.ui(15))
                        .foregroundStyle(Noel.cream.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        if scenario.isFree {
                            Text("Free").font(.ui(12, .bold)).foregroundStyle(Noel.goldLight)
                        } else if locked {
                            PremiumTag()
                        }
                        Text(scenario.minutes).font(.ui(12, .medium)).foregroundStyle(Noel.cream.opacity(0.55))
                    }
                    .padding(.top, 2)
                }
                .multilineTextAlignment(.leading)

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(selected ? Noel.gold : Noel.cream.opacity(0.25))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(selected ? Color(red: 0.11, green: 0.20, blue: 0.27).opacity(0.92) : Noel.night.opacity(0.62))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(selected ? AnyShapeStyle(Noel.goldGradient) : AnyShapeStyle(Noel.cream.opacity(0.12)), lineWidth: selected ? 2 : 1)
            )
            .shadow(color: Noel.gold.opacity(selected ? 0.35 : 0), radius: 14)
            .scaleEffect(selected ? 1.0 : 0.985)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
