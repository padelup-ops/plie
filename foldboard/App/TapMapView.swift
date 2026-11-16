import SwiftUI

/// « Où tu tapes » : la carte de tes appuis sur chaque touche, et de combien le clavier décale ses touches pour toi.
struct TapMapView: View {
    @Environment(SettingsModel.self) private var model
    @State private var map = KBVault.loadTaps() ?? KBTapMap()
    @State private var showTaps = true
    @State private var confirmReset = false

    var body: some View {
        @Bindable var m = model
        List {
            Section {
                Picker("", selection: $showTaps) {
                    Text("Keys").tag(false)
                    Text("Taps").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
                TapKeyboard(map: map, layout: model.settings.layout, showTaps: showTaps)
                    .frame(height: 210)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            } footer: {
                Text(showTaps
                     ? "Each dot is a tap on that key, in a word you kept without correction. The cross is the middle of your taps."
                     : "Each key sits where you really tap it; the grey outline is where it is drawn.")
            }

            Section {
                Toggle("Adjust the keys to where I tap", isOn: $m.settings.tapLearn)
                LabeledContent("Taps recorded", value: "\(map.total)")
                LabeledContent("One hand", value: offsetText(map.shift(twoHands: false)))
                LabeledContent("Two hands", value: offsetText(map.shift(twoHands: true)))
                LabeledContent("Space bar", value: map.spaceRaise > 0
                               ? String(format: NSLocalizedString("%lld%% higher", comment: ""), Int((map.spaceRaise * 100).rounded()))
                               : (map.space.n >= 20 ? NSLocalizedString("Centered", comment: "") : NSLocalizedString("Not enough taps yet", comment: "")))
            } footer: {
                Text("Nothing to set up: every word you type that needs no correction teaches it. After 30 letters, the keys move toward where you really tap, by a third of a key at most. Only where each tap lands on its key is kept, never what you write, and it stays on your iPhone.")
            }

            Section {
                Button("Reset where I tap", role: .destructive) { confirmReset = true }
                    .confirmationDialog("Reset where you tap?", isPresented: $confirmReset, titleVisibility: .visible) {
                        Button("Reset", role: .destructive) {
                            map = KBTapMap()
                            KBVault.saveTaps(map)
                        }
                    }
            }
        }
        .navigationTitle("Where you tap")
        .onAppear { map = KBVault.loadTaps() ?? KBTapMap() }
    }

    private func offsetText(_ s: (dx: Double, dy: Double)?) -> String {
        guard let s else { return NSLocalizedString("Not enough taps yet", comment: "") }
        var parts: [String] = []
        let x = Int((abs(s.dx) * 100).rounded()), y = Int((abs(s.dy) * 100).rounded())
        if x >= 2 { parts.append(String(format: NSLocalizedString(s.dx < 0 ? "%lld%% left" : "%lld%% right", comment: ""), x)) }
        if y >= 2 { parts.append(String(format: NSLocalizedString(s.dy < 0 ? "%lld%% higher" : "%lld%% lower", comment: ""), y)) }
        return parts.isEmpty ? NSLocalizedString("Centered", comment: "") : parts.joined(separator: ", ")
    }
}

/// Le clavier dessiné, avec les appuis (points), leur milieu (croix) ou les touches déplacées là où tu tapes.
private struct TapKeyboard: View {
    let map: KBTapMap
    let layout: KBLayout
    let showTaps: Bool

    var body: some View {
        Canvas { ctx, size in
            let rows = KBLayouts.rows(.letters, layout: layout, numberRow: false)
            let n = Double(rows.count)
            let gap = 4.0
            let keyH = (size.height - gap * (n - 1)) / n
            let unitW = size.width / 10
            let shift = map.shift(twoHands: true) ?? map.shift(twoHands: false)
            for (r, row) in rows.enumerated() {
                let rowW = row.keys.reduce(0) { $0 + $1.width } + 2 * row.inset
                var x = (size.width - rowW * unitW) / 2 + row.inset * unitW
                let y = Double(r) * (keyH + gap)
                for k in row.keys {
                    let w = k.width * unitW
                    let rect = CGRect(x: x + gap / 2, y: y, width: w - gap, height: keyH)
                    let name: String?
                    switch k.kind {
                    case .char(let s) where s.count == 1 && s.first?.isLetter == true: name = s.lowercased()
                    case .space: name = " "
                    default: name = nil
                    }
                    let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
                    if showTaps || name == nil {
                        ctx.fill(shape.path(in: rect), with: .color(Color.secondary.opacity(0.18)))
                    } else {
                        // Les touches déplacées là où tu tapes ; le contour gris, là où elles sont dessinées.
                        ctx.stroke(shape.path(in: rect), with: .color(Color.secondary.opacity(0.5)), lineWidth: 1)
                        var moved = rect
                        if name == " " {
                            moved.origin.y -= CGFloat(map.spaceRaise) * rect.height
                        } else if let s = shift {
                            moved.origin.x += CGFloat(s.dx) * rect.width
                            moved.origin.y += CGFloat(s.dy) * rect.height
                        }
                        ctx.fill(shape.path(in: moved), with: .color(Color.accentColor.opacity(0.75)))
                    }
                    if let name, name != " " || !showTaps {
                        if name != " " {
                            ctx.draw(Text(name).font(.system(size: 13, weight: .medium)).foregroundColor(.secondary),
                                     at: CGPoint(x: rect.midX, y: rect.midY))
                        }
                    }
                    if showTaps, let name, let taps = map.keys[name], !taps.isEmpty {
                        var sx = 0.0, sy = 0.0
                        for t in taps where t.count == 2 {
                            let px = rect.midX + CGFloat(t[0]) * rect.width, py = rect.midY + CGFloat(t[1]) * rect.height
                            sx += Double(t[0]); sy += Double(t[1])
                            ctx.fill(Path(ellipseIn: CGRect(x: px - 2.5, y: py - 2.5, width: 5, height: 5)),
                                     with: .color(Color.accentColor.opacity(0.55)))
                        }
                        if taps.count >= 5 {
                            let cx = rect.midX + CGFloat(sx / Double(taps.count)) * rect.width
                            let cy = rect.midY + CGFloat(sy / Double(taps.count)) * rect.height
                            var p = Path()
                            p.move(to: CGPoint(x: cx - 5, y: cy)); p.addLine(to: CGPoint(x: cx + 5, y: cy))
                            p.move(to: CGPoint(x: cx, y: cy - 5)); p.addLine(to: CGPoint(x: cx, y: cy + 5))
                            ctx.stroke(p, with: .color(.primary), lineWidth: 1.5)
                        }
                    }
                    x += w
                }
            }
        }
        .accessibilityLabel(Text("Where you tap"))
    }
}
