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
                VStack(spacing: 14) {
                    Text("Home Screen").vfHUD(VF.textDim).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 22)
                    // Les tuiles gardent leurs proportions et rétrécissent ensemble sur un écran étroit.
                    ViewThatFits(in: .horizontal) {
                        tiles(snap, unit: 158)
                        tiles(snap, unit: 142)
                        tiles(snap, unit: 126)
                    }
                }
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity)
                .background {
                    ZStack {
                        SynthScene(time: 0, sunrise: 1, palms: false, horizon: 0.74).opacity(0.55)
                        VF.abyss.opacity(0.35)
                    }
                    .clipShape(.rect(cornerRadius: 34, style: .continuous))
                }
                .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).stroke(VF.hairline, lineWidth: 1))

                // L'écran verrouillé
                VStack(spacing: 12) {
                    Text("Lock Screen").vfHUD(VF.textDim).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 22)
                    Text(ShotMode.route != nil ? Calendar.current.date(bySettingHour: 9, minute: 41, second: 0, of: Date()) ?? Date() : Date(), format: .dateTime.hour().minute())
                        .font(.system(size: 64, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    HStack(spacing: 12) {
                        VFWidgetFace(snap: snap, size: .circular).frame(width: 64, height: 64)
                        VFWidgetFace(snap: snap, size: .rectangular).frame(width: 170, height: 64)
                    }
                    .foregroundStyle(.white)
                    .tint(.white)
                }
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity)
                .background(LinearGradient(colors: [VF.panel, Color(red: 0.20, green: 0.06, blue: 0.30)], startPoint: .top, endPoint: .bottom), in: .rect(cornerRadius: 34, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).stroke(VF.hairline, lineWidth: 1))

                Label("Touch and hold the Home Screen, tap Edit, then Add Widget.", systemImage: "hand.tap")
                    .font(.footnote).foregroundStyle(VF.textDim).multilineTextAlignment(.leading)
                    .vfCard(radius: 18, padding: 14)
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

    private func tiles(_ snap: VFSnapshot, unit: CGFloat) -> some View {
        let gap = unit * 0.1
        let wide = unit * 2 + gap
        return VStack(spacing: gap) {
            HStack(spacing: gap) {
                tile(w: unit, h: unit) { VFWidgetFace(snap: snap, size: .small) }
                tile(w: unit, h: unit) { VFDaysFace(days: VFDaysFace.days()) }
            }
            tile(w: wide, h: unit) { VFWidgetFace(snap: snap, size: .medium) }
            tile(w: wide, h: unit * 2.2) { VFWidgetFace(snap: snap, size: .large) }
        }
        .frame(width: wide)
    }

    private func tile<Face: View>(w: CGFloat, h: CGFloat, @ViewBuilder face: () -> Face) -> some View {
        face()
            .padding(16)
            .frame(width: w, height: h)
            .background(VFWidgetBackground())
            .clipShape(.rect(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(VF.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
    }
}
