import SwiftUI
import UIKit

/// Essayer le coup sur le bord de l'iPhone et régler la sensibilité : chaque coup vu s'affiche (le côté
/// reconnu, ou pourquoi il n'a pas compté), et une jauge montre la force des coups par rapport au seuil.
struct KnockTestView: View {
    @Environment(SettingsModel.self) private var model
    @State private var knock = KBKnock()
    @State private var last: KBKnockProbe?
    @State private var lit: Bool?
    @State private var level = 0.0
    @State private var peak = 0.0
    @State private var hits = 0
    @State private var copied = false

    var body: some View {
        @Bindable var m = model
        List {
            Section {
                VStack(spacing: 16) {
                    phone
                    Text(status)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(last?.accepted == false ? Color.orange : Color.primary)
                        .frame(minHeight: 44)
                    meter
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            } footer: {
                Text("Hold the iPhone in one hand, as you type. Knock its left or right edge (the frame, not the screen) with a fingertip.")
            }
            Section {
                Slider(value: $m.settings.knockSensitivity, in: 0...1) {
                    Text("Sensitivity")
                } minimumValueLabel: {
                    Text("Firm").font(.footnote)
                } maximumValueLabel: {
                    Text("Light").font(.footnote)
                }
            } header: {
                Text("Sensitivity")
            } footer: {
                Text("Nothing happens? Move it toward Light. The keyboard moves by itself while you type? Move it toward Firm.")
            }
            Section {
                Button {
                    UIPasteboard.general.string = (["Foldboard knock", UIDevice.current.model] + knock.log).joined(separator: "\n")
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy the data for the developer", systemImage: copied ? "checkmark" : "doc.on.clipboard")
                }
                .disabled(knock.log.isEmpty && !copied)
            } footer: {
                Text("Only the strength of each knock, never what you type.")
            }
        }
        .navigationTitle("Try knocking")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: start)
        .onDisappear { knock.stop(); knock.onLevel = nil; knock.onProbe = nil }
        .onChange(of: model.settings.knockSensitivity) { _, v in knock.sensitivity = v }
    }

    private func start() {
        knock.sensitivity = model.settings.knockSensitivity
        knock.onLevel = { v in
            level = v
            peak = max(peak * 0.85, v)
        }
        knock.onProbe = { p in
            last = p
            copied = false
            guard p.accepted else { return }
            hits += 1
            // Le bord tapé : le premier pic part de ce côté (mesuré sur un vrai Duo). Sur l'écran intérieur du Duo, les
            // axes sont inversés (comme dans le clavier).
            let left = Self.innerScreen ? p.pushedRight : !p.pushedRight
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeOut(duration: 0.15)) { lit = left }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                withAnimation(.easeIn(duration: 0.3)) { if lit == left { lit = nil } }
            }
        }
        knock.start()
    }

    private static var innerScreen: Bool {
        let s = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen.bounds.size }.first ?? .zero
        return min(s.width, s.height) >= 600
    }

    private var status: LocalizedStringKey {
        guard let p = last else { return "Knock the left or right edge…" }
        if p.accepted {
            let left = Self.innerScreen ? p.pushedRight : !p.pushedRight
            return left ? "Left edge ✓" : "Right edge ✓"
        }
        switch p.reason {
        case "screen": return "Seen, but it looked like a touch on the screen. Knock the frame, on the side."
        case "touch": return "Ignored: a finger was on the screen."
        case "moving": return "Ignored: the iPhone was moving. Hold it still, then knock."
        case "long": return "Too slow: knock briskly, like on a door."
        default: return "Too soon after the last one."
        }
    }

    /// Le téléphone vu de face : le bord reconnu s'allume.
    private var phone: some View {
        HStack(spacing: 10) {
            edge(lit == true)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.7), lineWidth: 3)
                .frame(width: 92, height: 180)
                .overlay(Text("\(hits)").font(.title.monospacedDigit().bold()).foregroundStyle(.secondary))
            edge(lit == false)
        }
    }

    private func edge(_ on: Bool) -> some View {
        Capsule()
            .fill(on ? Color.orange : Color.secondary.opacity(0.25))
            .frame(width: 8, height: on ? 120 : 90)
            .shadow(color: on ? .orange.opacity(0.7) : .clear, radius: 8)
    }

    /// La force des coups : la barre doit passer le trait pour que le coup compte.
    private var meter: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule().fill(Color.orange.opacity(0.35)).frame(width: w * min(1, peak / 2))
                Capsule().fill(Color.orange).frame(width: w * min(1, level / 2))
                Rectangle().fill(Color.primary).frame(width: 2, height: 18).offset(x: w / 2 - 1)
            }
        }
        .frame(height: 12)
        .padding(.horizontal, 24)
        .accessibilityElement()
        .accessibilityLabel(Text("Knock strength"))
        .accessibilityValue(Text(level >= 1 ? "Enough" : "Too light"))
    }
}
