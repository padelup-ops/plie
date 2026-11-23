// WidgetGallery.swift — Vicefold
//
// L'aperçu des widgets avec ta vraie progression : sur un écran d'accueil (petit, moyen, grand) et sur l'écran
// verrouillé. Ouvert depuis le profil ; sert aussi aux captures.

import SwiftUI

struct WidgetGallery: View {
    @Environment(Progress.self) private var progress
    @Environment(\.dismiss) private var dismiss
    var closable = false

    var body: some View {
        let snap = progress.snapshot()
        ScrollView {
            VStack(spacing: 22) {
                // L'écran d'accueil
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        tile(snap, .small, w: 158, h: 158)
                        tile(snap, .small, w: 158, h: 158, days: true)
                    }
                    tile(snap, .medium, w: 332, h: 158)
                    tile(snap, .large, w: 332, h: 348)
                }
                .padding(.vertical, 26)
                .frame(maxWidth: .infinity)
                .background(VF.dusk.opacity(0.9), in: .rect(cornerRadius: 34))

                // L'écran verrouillé
                VStack(spacing: 12) {
                    Text(ShotMode.route != nil ? Calendar.current.date(bySettingHour: 9, minute: 41, second: 0, of: Date()) ?? Date() : Date(), format: .dateTime.hour().minute()).font(.system(size: 64, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                    HStack(spacing: 12) {
                        VFWidgetFace(snap: snap, size: .circular).frame(width: 64, height: 64)
                        VFWidgetFace(snap: snap, size: .rectangular).frame(width: 170, height: 64)
                    }
                    .foregroundStyle(.white)
                    .environment(\.colorScheme, .dark)
                }
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
                .background(LinearGradient(colors: [VF.ink, Color(red: 0.25, green: 0.12, blue: 0.35)], startPoint: .top, endPoint: .bottom), in: .rect(cornerRadius: 34))

                Text("Touch and hold the Home Screen, tap Edit, then Add Widget.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(VFBackdrop())
        .navigationTitle("Progress widgets")
        .toolbar {
            if closable {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func tile(_ s: VFSnapshot, _ size: VFWidgetSize, w: CGFloat, h: CGFloat, days: Bool = false) -> some View {
        Group {
            if days {
                let d = VFWidgetFace.dayInLeonida()
                VStack(spacing: 0) {
                    Text("\(d)").font(VF.display(56)).monospacedDigit().foregroundStyle(VF.gradient)
                    Text("days in Leonida").font(.caption.weight(.semibold))
                }
            } else {
                VFWidgetFace(snap: s, size: size)
            }
        }
        .padding(16)
        .frame(width: w, height: h)
        .background(VFWidgetBackground())
        .clipShape(.rect(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }
}
