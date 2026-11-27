// TrackerView.swift — Vicefold
//
// Le suivi : missions par chapitre (avec leurs objectifs), objets à collectionner, défis, et l'anneau 100 % en tubes
// de néon, à partager en image.

import PhotosUI
import SwiftUI

struct TrackerView: View {
    @Environment(ContentStore.self) private var content
    @State private var selected: VFMission?

    var body: some View {
        DualLayout {
            TrackerList(selected: $selected)
        } secondary: {
            NavigationStack {
                if let m = selected { MissionDetail(mission: m).id(m.id) } else { TrackerSummary() }
            }
        }
        .onAppear {
            if ShotMode.route == "mission", selected == nil { selected = content.missions.first }
        }
    }
}

private enum TrackerSection: String, CaseIterable, Identifiable {
    case missions, collectibles, challenges
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .missions: return "Missions"
        // « Objets » plutôt que « Objets à collectionner » : le mot long était coupé dans le sélecteur.
        case .collectibles: return "Items"
        case .challenges: return "Challenges"
        }
    }
}

private struct TrackerList: View {
    @Binding var selected: VFMission?
    @Environment(\.vfWide) private var wide
    @Environment(ContentStore.self) private var content
    @Environment(Progress.self) private var progress
    @State private var section: TrackerSection = ShotMode.route == "collectibles" ? .collectibles : (ShotMode.route == "challenges" ? .challenges : .missions)
    @State private var push: VFMission?
    @State private var share = ShotMode.route == "share"
    // Le filtre reste d'une ouverture à l'autre.
    @AppStorage("vicefold.hideDone") private var hideDone = false

    var body: some View {
        NavigationStack {
            List {
                Group {
                    if !wide {
                        Section { TrackerSummary(compact: true) }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                    Picker("Section", selection: $section) {
                        ForEach(TrackerSection.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                    switch section {
                    case .missions: missions
                    case .collectibles: CollectibleRows(hideDone: hideDone)
                    case .challenges: challenges
                    }
                }
                .vfRows()
            }
            .navigationTitle("Tracker")
            .vfScreen()
            .navigationDestination(item: $push) { MissionDetail(mission: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Hide completed", isOn: $hideDone)
                        Button { share = true } label: { Label("Share my progress", systemImage: "square.and.arrow.up") }
                    } label: { Image(systemName: hideDone ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle") }
                        .accessibilityLabel("Hide completed")
                }
            }
            .sheet(isPresented: $share) { ShareProgressView() }
        }
    }

    @ViewBuilder private var missions: some View {
        let left = content.missions.contains { !progress.isDone($0) }
        if hideDone && !left && !content.missions.isEmpty {
            Section { VFEmptyState(icon: "checkmark.seal.fill", title: "All missions done", message: "Turn off \"Hide completed\" to see them again.").listRowBackground(Color.clear) }
        }
        ForEach(content.chapters) { ch in
            let all = content.missions(in: ch.id)
            let ms = all.filter { !hideDone || !progress.isDone($0) }
            if !ms.isEmpty {
                Section {
                    ForEach(ms) { m in
                        let hidden = progress.hidden(m.chapter)
                        let done = progress.isDone(m)
                        HStack(spacing: 12) {
                            Button { progress.toggle(m) } label: { CheckMark(done: done, color: VF.palm) }
                                .buttonStyle(.plain)
                                .accessibilityLabel(done ? "Done" : "Not done")
                            Button { open(m) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(hidden ? String(localized: "Hidden mission") : m.title)
                                            .foregroundStyle(done ? VF.textDim : VF.text)
                                        if !hidden, let g = m.giver { Text(g).font(.caption).foregroundStyle(VF.textFaint) }
                                    }
                                    Spacer()
                                    if m.optional == true {
                                        Text("Optional").font(VF.mono(9.5, weight: .bold)).textCase(.uppercase).foregroundStyle(VF.sun)
                                            .padding(.horizontal, 6).padding(.vertical, 3)
                                            .overlay(Capsule().stroke(VF.sun.opacity(0.5), lineWidth: 1))
                                    }
                                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(VF.textFaint)
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                        .listRowBackground(selected == m && wide ? VF.rowSelected : VF.row)
                    }
                } header: {
                    let done = all.filter { progress.isDone($0) }.count
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(progress.hidden(ch.id) ? String(localized: "Chapter \(ch.id)") : ch.title)
                            Spacer()
                            Text(verbatim: "\(done)/\(all.count)").font(VF.mono(11, weight: .bold)).foregroundStyle(done == all.count ? VF.palm : VF.textDim)
                        }
                        VFBar(value: Double(done) / Double(max(1, all.count)), color: VF.flamingo, height: 3)
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        if content.missions.isEmpty {
            Section { VFEmptyState(icon: "flag", title: "No missions yet", message: "They arrive with a content update, no app update needed.").listRowBackground(Color.clear) }
        }
    }

    @ViewBuilder private var challenges: some View {
        // Dans l'ordre du guide (pas l'ordre alphabétique, qui change d'une langue à l'autre).
        let list = content.content.challenges
        let groups = list.reduce(into: [String]()) { if !$0.contains($1.group) { $0.append($1.group) } }
        let left = list.contains { !progress.challengeDone($0) }
        if hideDone && !left && !list.isEmpty {
            Section { VFEmptyState(icon: "checkmark.seal.fill", title: "All challenges done", message: "Turn off \"Hide completed\" to see them again.").listRowBackground(Color.clear) }
        }
        ForEach(groups, id: \.self) { g in
            let items = list.filter { $0.group == g && (!hideDone || !progress.challengeDone($0)) }
            if !items.isEmpty {
                Section(g) {
                    ForEach(items) { c in
                        let done = progress.challengeDone(c)
                        Button { progress.toggle(c) } label: {
                            HStack(spacing: 12) {
                                CheckMark(done: done, color: VF.sky)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.title).foregroundStyle(done ? VF.textDim : VF.text)
                                    if let d = c.detail { Text(d).font(.caption).foregroundStyle(VF.textFaint) }
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(done ? .isSelected : [])
                    }
                }
            }
        }
        if list.isEmpty {
            Section { VFEmptyState(icon: "stopwatch", title: "No challenges yet", message: "They arrive with a content update, no app update needed.").listRowBackground(Color.clear) }
        }
    }

    private func open(_ m: VFMission) {
        if wide { selected = m } else { push = m }
    }
}

/// La coche d'une ligne : un anneau vide, ou un disque plein qui luit.
struct CheckMark: View {
    var done: Bool
    var color: Color = VF.palm

    var body: some View {
        Image(systemName: done ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(done ? color : VF.textFaint)
            .shadow(color: done ? color.opacity(0.7) : .clear, radius: 5)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 30, height: 30)
            .contentShape(.rect)
    }
}

/// L'anneau 100 % et ses quatre parts.
struct TrackerSummary: View {
    var compact = false
    @Environment(ContentStore.self) private var content
    @Environment(Progress.self) private var progress
    @State private var share = false

    var body: some View {
        if compact {
            HStack(spacing: 14) {
                ring(size: 112, line: 6)
                stats
            }
            .vfCard(radius: 22, padding: 14)
        } else {
            ScrollView {
                VStack(spacing: 26) {
                    ring(size: 250, line: 15)
                    stats.frame(maxWidth: 380).vfCard(radius: 22, padding: 18)
                    Button { share = true } label: { Label("Share as an image", systemImage: "square.and.arrow.up").frame(maxWidth: 300) }
                        .buttonStyle(.vfPrimary)
                }
                .padding(30)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .background(VFBackdrop())
            .navigationTitle("Your 100%")
            .sheet(isPresented: $share) { ShareProgressView() }
        }
    }

    private func ring(size: CGFloat, line: CGFloat) -> some View {
        let p = progress.parts(content.content)
        return ZStack {
            VFRing(parts: p.all, lineWidth: line, gap: max(2.5, line * 0.3))
            VStack(spacing: 2) {
                Text(p.total, format: .percent.precision(.fractionLength(0)))
                    .font(VF.display(size * 0.2)).monospacedDigit()
                    .foregroundStyle(VF.gradient)
                    .shadow(color: VF.flamingo.opacity(0.55), radius: 8)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                if size > 150 { Text("of the game").vfHUD(VF.textDim, size: 10) }
            }
            .frame(width: size * 0.34)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(p.total, format: .percent.precision(.fractionLength(0))))
    }

    private var stats: some View {
        let p = progress.parts(content.content)
        let c = content.content
        let found = c.collectibles.reduce(0) { $0 + min($1.target, progress.found($1)) }
        // Les défis comptés sont ceux du guide (une ancienne coche qui n'existe plus ne compte pas).
        let challenges = c.challenges.filter { progress.challengeDone($0) }.count
        return VStack(alignment: .leading, spacing: 10) {
            stat("Missions", p.missions, 0, detail: "\(content.storyMissions.filter { progress.isDone($0) }.count)/\(content.storyMissions.count)")
            stat("Places", p.places, 1, detail: "\(content.countedPlaces.filter { progress.visited($0) }.count)/\(content.countedPlaces.count)")
            stat("Items", p.collectibles, 2, detail: "\(found)/\(content.totalCollectibles)")
            stat("Challenges", p.challenges, 3, detail: "\(challenges)/\(c.challenges.count)")
        }
    }

    private func stat(_ name: LocalizedStringKey, _ v: Double, _ i: Int, detail: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(VF.text).lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 4)
                Text(verbatim: detail).font(VF.mono(10)).foregroundStyle(VF.textDim).lineLimit(1).fixedSize()
                Text(v, format: .percent.precision(.fractionLength(0))).font(VF.mono(12, weight: .bold)).foregroundStyle(VF.ringColors[i])
                    .lineLimit(1).frame(minWidth: 38, alignment: .trailing)
            }
            VFBar(value: v, color: VF.ringColors[i], gradient: false, height: 3)
        }
        .accessibilityElement(children: .combine)
    }
}

struct MissionDetail: View {
    var mission: VFMission
    @Environment(ContentStore.self) private var content
    @Environment(Progress.self) private var progress
    @State private var revealed = false

    var body: some View {
        let hidden = progress.hidden(mission.chapter) && !revealed
        let done = progress.isDone(mission)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let c = content.chapter(mission.chapter) {
                    Text(hidden ? String(localized: "Chapter \(c.id)") : c.title).vfHUD(VF.cyan, size: 11)
                }
                if hidden {
                    Text("Hidden mission").font(VF.display(40)).foregroundStyle(VF.text)
                    SpoilerGate(chapter: mission.chapter) { revealed = true }
                } else {
                    Text(mission.title).font(VF.display(40)).foregroundStyle(VF.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if mission.giver != nil || mission.location != nil {
                        VStack(alignment: .leading, spacing: 6) {
                            if let g = mission.giver { Label(g, systemImage: "person.fill") }
                            if let l = mission.location { Label(l, systemImage: "mappin.and.ellipse") }
                        }
                        .font(.subheadline)
                        .foregroundStyle(VF.textDim)
                    }
                    if !mission.objectives.isEmpty { objectives }
                    if let w = mission.walkthrough {
                        SectionTitle(title: "Walkthrough").padding(.top, 4)
                        MarkdownBlocks(text: w)
                    }
                    if let tips = mission.tips, !tips.isEmpty {
                        MarkdownBlocks(text: tips.map { "> " + $0 }.joined(separator: "\n"))
                    }
                    if let u = mission.unlocks {
                        Label(u, systemImage: "lock.open.fill").font(.subheadline).foregroundStyle(VF.palm)
                            .vfCard(radius: 16, padding: 12, tint: VF.palm)
                    }
                    // Coincé ? Des parties filmées par les joueurs, sur YouTube (on n'héberge aucune image du jeu).
                    Link(destination: Self.youtube(mission)) {
                        linkRow(icon: "play.rectangle.fill", color: Color(red: 1, green: 0.32, blue: 0.32), title: "Stuck? Watch it on YouTube",
                                text: "Opens player walkthroughs of this mission on YouTube.", trailing: "arrow.up.right", count: nil)
                    }
                    .buttonStyle(.plain)
                    // L'entraide : le fil de cette mission.
                    NavigationLink { ThreadView(topic: mission.id, title: mission.title, chapter: mission.chapter) } label: {
                        linkRow(icon: "bubble.left.and.bubble.right.fill", color: VF.flamingo, title: "Players' questions",
                                text: "Ask the community or help someone stuck here.", trailing: "chevron.right", count: CommunityStore.shared.counts[mission.id])
                    }
                    .buttonStyle(.plain)
                    MissionShots(mission: mission)
                }
                Button { progress.toggle(mission) } label: {
                    Label(done ? "Completed" : "Mark as completed", systemImage: done ? "checkmark.circle.fill" : "circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.vf(done ? .done : .primary))
                .padding(.top, 8)
            }
            .padding()
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationBarTitleDisplayMode(.inline)
        .background(VFBackdrop())
        .onAppear { Recents.shared.opened(.mission, mission.id) }
    }

    private var objectives: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Objectives").font(.headline).foregroundStyle(VF.text)
                Spacer()
                Text(verbatim: "\(mission.objectives.indices.filter { progress.objectiveDone(mission, $0) }.count)/\(mission.objectives.count)")
                    .font(VF.mono(11, weight: .bold)).foregroundStyle(VF.cyan)
            }
            .padding(.bottom, 8)
            ForEach(Array(mission.objectives.enumerated()), id: \.offset) { i, o in
                let ok = progress.objectiveDone(mission, i)
                Button { progress.toggleObjective(mission, i) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: ok ? "checkmark.square.fill" : "square")
                            .foregroundStyle(ok ? VF.palm : VF.textFaint)
                            .shadow(color: ok ? VF.palm.opacity(0.6) : .clear, radius: 4)
                        Text(o).foregroundStyle(ok ? VF.textDim : VF.text).strikethrough(ok).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 7)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(ok ? .isSelected : [])
            }
        }
        .vfCard(radius: 18, padding: 16)
    }

    private func linkRow(icon: String, color: Color, title: LocalizedStringKey, text: LocalizedStringKey, trailing: String, count: Int?) -> some View {
        HStack(spacing: 12) {
            VFIconBadge(icon: icon, color: color, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(VF.text).multilineTextAlignment(.leading)
                Text(text).font(.caption).foregroundStyle(VF.textDim).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            if let count, count > 0 {
                Text(verbatim: "\(count)").font(VF.mono(11, weight: .bold)).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(color.opacity(0.16), in: .capsule).foregroundStyle(color)
            }
            Image(systemName: trailing).font(.footnote.weight(.bold)).foregroundStyle(VF.textFaint)
        }
        .vfCard(radius: 18, padding: 14)
    }

    /// Une recherche YouTube « GTA 6 <mission> » : les vidéos des joueurs, ouvertes dans YouTube ou Safari.
    static func youtube(_ m: VFMission) -> URL {
        var c = URLComponents(string: "https://www.youtube.com/results")!
        c.queryItems = [URLQueryItem(name: "search_query", value: "GTA 6 \"\(m.title)\" mission walkthrough")]
        return c.url!
    }
}

/// Les objets à collectionner et le reste du 100 % : un compteur par série, rangé par groupe.
struct CollectibleRows: View {
    var hideDone = false
    @Environment(ContentStore.self) private var content
    @Environment(Progress.self) private var progress

    var body: some View {
        let sets = content.content.collectibles.filter { !hideDone || progress.found($0) < $0.target }
        let groups = sets.reduce(into: [String]()) { let g = $1.group ?? ""; if !$0.contains(g) { $0.append(g) } }
        ForEach(groups, id: \.self) { g in
            Section {
                ForEach(sets.filter { ($0.group ?? "") == g }) { s in row(s) }
            } header: {
                if !g.isEmpty { Text(g) }
            }
        }
        if content.content.collectibles.isEmpty {
            Section { VFEmptyState(icon: "sparkles", title: "No collectibles yet", message: "They arrive with a content update, no app update needed.").listRowBackground(Color.clear) }
        } else if sets.isEmpty {
            Section { VFEmptyState(icon: "checkmark.seal.fill", title: "Everything found", message: "Turn off \"Hide completed\" to see them again.").listRowBackground(Color.clear) }
        }
    }

    private func row(_ s: VFCollectibleSet) -> some View {
        let n = progress.found(s)
        let complete = n >= s.target
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(s.title).font(.headline).foregroundStyle(VF.text).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(verbatim: "\(n)/\(s.target)").font(VF.mono(13, weight: .bold)).foregroundStyle(complete ? VF.palm : VF.sun)
                    .contentTransition(.numericText())
                Stepper(s.title, value: Binding(get: { progress.found(s) }, set: { progress.setFound(s, $0) }), in: 0...max(s.count, s.target))
                    .labelsHidden()
            }
            VFBar(value: Double(min(n, s.target)) / Double(max(1, s.target)), color: complete ? VF.palm : VF.sun, gradient: false, height: 4)
            if let sum = s.summary { Text(sum).font(.footnote).foregroundStyle(VF.textDim) }
            if let r = s.reward { Label(r, systemImage: "gift.fill").font(.footnote).foregroundStyle(VF.flamingo) }
        }
        .padding(.vertical, 4)
    }
}

struct CollectiblesView: View {
    var body: some View {
        List { CollectibleRows().vfRows() }.navigationTitle("Collectibles").vfScreen()
    }
}

/// L'image à partager : l'anneau en néon, les quatre parts, le temps de jeu, sur un horizon quadrillé.
struct ShareProgressView: View {
    @Environment(ContentStore.self) private var content
    @Environment(Progress.self) private var progress
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var scale
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    card.frame(width: 340, height: 440)
                        .clipShape(.rect(cornerRadius: 28, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(VF.hairline, lineWidth: 1))
                        .shadow(color: VF.flamingo.opacity(0.35), radius: 30, y: 10)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("My Leonida progress")
                    if let img = image {
                        ShareLink(item: Image(uiImage: img), preview: SharePreview(String(localized: "My Leonida progress"), image: Image(uiImage: img))) {
                            Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: 280)
                        }
                        .buttonStyle(.vfPrimary)
                    } else {
                        ProgressView().frame(height: 50)
                    }
                }
                .padding()
                .padding(.top, 8)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(VFBackdrop(vivid: true))
            .navigationTitle("Share my progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            // L'image est rendue une fois, à l'ouverture (pas à chaque redessin de l'écran).
            .task { image = render() }
        }
    }

    @MainActor private func render() -> UIImage? {
        let r = ImageRenderer(content: card.frame(width: 340, height: 440).environment(content).environment(progress).environment(\.colorScheme, .dark))
        r.scale = max(3, scale)
        return r.uiImage
    }

    private var card: some View {
        let p = progress.parts(content.content)
        let name = progress.data.name.trimmingCharacters(in: .whitespaces)
        return ZStack {
            SynthScene(time: 0, sunrise: 0.25, palms: false, horizon: 0.80)
            LinearGradient(colors: [VF.abyss.opacity(0.55), VF.abyss.opacity(0)], startPoint: .top, endPoint: .center)
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Avatar(size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name.isEmpty ? String(localized: "My game") : name).font(.headline).foregroundStyle(VF.text).lineLimit(1)
                        if progress.hours > 0 { Text("\(Int(progress.hours)) h played").font(VF.mono(10)).foregroundStyle(VF.textDim) }
                    }
                    Spacer()
                    Text("Day \(VFWidgetFace.dayInLeonida()) in Leonida").font(VF.mono(9, weight: .bold)).textCase(.uppercase).foregroundStyle(VF.cyan)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .overlay(Capsule().stroke(VF.cyan.opacity(0.5), lineWidth: 1))
                }
                Spacer(minLength: 8)
                ZStack {
                    VFRing(parts: p.all, lineWidth: 10, gap: 3)
                    VStack(spacing: 0) {
                        Text(p.total, format: .percent.precision(.fractionLength(0))).font(VF.display(40)).monospacedDigit()
                            .foregroundStyle(VF.gradient).shadow(color: VF.flamingo.opacity(0.6), radius: 10)
                        Text("of Leonida").font(VF.mono(9)).textCase(.uppercase).foregroundStyle(VF.textDim)
                    }
                }
                .frame(width: 184, height: 184)
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    mini("Missions", p.missions, 0); mini("Places", p.places, 1); mini("Items", p.collectibles, 2); mini("Challenges", p.challenges, 3)
                }
                Spacer(minLength: 0)
                    .frame(height: 50)
                VStack(spacing: 3) {
                    NeonWordmark(lit: [], size: 24)
                    Text("Unofficial fan companion").font(VF.mono(7.5)).tracking(1).textCase(.uppercase).foregroundStyle(VF.text.opacity(0.8))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)
        }
    }

    private func mini(_ t: LocalizedStringKey, _ v: Double, _ i: Int) -> some View {
        VStack(spacing: 2) {
            Text(v, format: .percent.precision(.fractionLength(0))).font(VF.mono(14, weight: .bold)).foregroundStyle(VF.ringColors[i])
                .shadow(color: VF.ringColors[i].opacity(0.6), radius: 5)
            Text(t).font(.system(size: 9, weight: .semibold)).foregroundStyle(VF.text.opacity(0.8)).lineLimit(1).minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Tes captures d'une mission : pour te rappeler laquelle c'est. Elles restent sur cet appareil.
struct MissionShots: View {
    var mission: VFMission
    @Environment(Progress.self) private var progress
    @State private var items: [PhotosPickerItem] = []
    @State private var viewing: String?

    var body: some View {
        let shots = progress.shots(mission)
        VStack(alignment: .leading, spacing: 10) {
            Text("My screenshots").font(.headline).foregroundStyle(VF.text)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(shots, id: \.self) { name in
                        Button { viewing = name } label: { thumb(name) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) { progress.removeShot(mission, name) }
                            }
                    }
                    if shots.count < Progress.maxShots {
                        PhotosPicker(selection: $items, maxSelectionCount: Progress.maxShots - shots.count, matching: .images) {
                            VStack(spacing: 6) {
                                Image(systemName: "camera.on.rectangle").font(.title2)
                                Text("Add").font(.caption.weight(.semibold))
                            }
                            .frame(width: 120, height: 76)
                            .foregroundStyle(VF.cyan)
                            .background(VF.cyan.opacity(0.10), in: .rect(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(VF.cyan.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                        }
                    }
                }
            }
            Text("Take a screenshot in the game (PS5: Create button) and add it here to remember this mission. Touch and hold one to delete it.")
                .font(.caption).foregroundStyle(VF.textDim)
        }
        .vfCard(radius: 18, padding: 16)
        .onChange(of: items) { _, picked in
            guard !picked.isEmpty else { return }
            Task {
                for it in picked {
                    if let data = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        let w: CGFloat = min(1800, img.size.width)
                        let jpg = img.preparingThumbnail(of: CGSize(width: w, height: w * img.size.height / max(1, img.size.width)))?.jpegData(compressionQuality: 0.8)
                        if let jpg { progress.addShot(mission, jpeg: jpg) }
                    }
                }
                items = []
            }
        }
        .fullScreenCover(item: Binding(get: { viewing.map { ShotName(id: $0) } }, set: { viewing = $0?.id })) { s in
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                if let img = UIImage(contentsOfFile: Progress.eggPhotoURL(s.id).path) {
                    Image(uiImage: img).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Button { viewing = nil } label: { Image(systemName: "xmark.circle.fill").font(.largeTitle).foregroundStyle(.white.opacity(0.85)) }
                    .padding()
                    .accessibilityLabel("Close")
            }
        }
    }

    private func thumb(_ name: String) -> some View {
        Group {
            if let img = UIImage(contentsOfFile: Progress.eggPhotoURL(name).path) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Color.white.opacity(0.08)
            }
        }
        .frame(width: 120, height: 76)
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(VF.hairline, lineWidth: 1))
    }

    private struct ShotName: Identifiable { var id: String }
}
