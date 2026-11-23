// TrackerView.swift — Vicefold
//
// Le suivi : missions par chapitre (avec leurs objectifs), objets à collectionner, défis, et l'anneau 100 % à partager
// en image.

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
        case .collectibles: return "Collectibles"
        case .challenges: return "Challenges"
        }
    }
}

private struct TrackerList: View {
    @Binding var selected: VFMission?
    @Environment(\.vfWide) private var wide
    @Environment(ContentStore.self) private var content
    @Environment(Progress.self) private var progress
    @State private var section: TrackerSection = ShotMode.route == "collectibles" ? .collectibles : .missions
    @State private var push: VFMission?
    @State private var share = ShotMode.route == "share"
    @State private var hideDone = false

    var body: some View {
        NavigationStack {
            List {
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
                case .collectibles: CollectibleRows()
                case .challenges: challenges
                }
            }
            .navigationTitle("Tracker")
            .scrollContentBackground(.hidden)
            .background(VFBackdrop())
            .navigationDestination(item: $push) { MissionDetail(mission: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Hide completed", isOn: $hideDone)
                        Button { share = true } label: { Label("Share my progress", systemImage: "square.and.arrow.up") }
                    } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                }
            }
            .sheet(isPresented: $share) { ShareProgressView() }
        }
    }

    @ViewBuilder private var missions: some View {
        ForEach(content.chapters) { ch in
            let ms = content.missions(in: ch.id).filter { !hideDone || !progress.isDone($0) }
            if !ms.isEmpty {
                Section {
                    ForEach(ms) { m in
                        let hidden = progress.hidden(m.chapter)
                        HStack(spacing: 12) {
                            Button { progress.toggle(m) } label: {
                                Image(systemName: progress.isDone(m) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(progress.isDone(m) ? VF.teal : .secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(progress.isDone(m) ? "Done" : "Not done")
                            Button { open(m) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(hidden ? String(localized: "Hidden mission") : m.title)
                                            .foregroundStyle(.primary)
                                            .blur(radius: hidden ? 0 : 0)
                                        if !hidden, let g = m.giver { Text(g).font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Spacer()
                                    if m.optional == true { Text("Optional").font(.caption2.weight(.semibold)).foregroundStyle(VF.sun) }
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                        .listRowBackground(selected == m && wide ? VF.coral.opacity(0.15) : nil)
                    }
                } header: {
                    let all = content.missions(in: ch.id)
                    let done = all.filter { progress.isDone($0) }.count
                    HStack {
                        Text(progress.hidden(ch.id) ? String(localized: "Chapter \(ch.id)") : ch.title)
                        Spacer()
                        Text("\(done)/\(all.count)").monospacedDigit()
                    }
                }
            }
        }
    }

    @ViewBuilder private var challenges: some View {
        let groups = Dictionary(grouping: content.content.challenges) { $0.group }
        ForEach(groups.keys.sorted(), id: \.self) { g in
            Section(g) {
                ForEach(groups[g] ?? []) { c in
                    if !hideDone || !progress.challengeDone(c) {
                        Button { progress.toggle(c) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: progress.challengeDone(c) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(progress.challengeDone(c) ? VF.magenta : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.title).foregroundStyle(.primary)
                                    if let d = c.detail { Text(d).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func open(_ m: VFMission) {
        if wide { selected = m } else { push = m }
    }
}

/// L'anneau 100 % et ses quatre parts.
struct TrackerSummary: View {
    var compact = false
    @Environment(ContentStore.self) private var content
    @Environment(Progress.self) private var progress
    @State private var share = false

    var body: some View {
        let p = progress.parts(content.content)
        let layout = compact ? AnyLayout(HStackLayout(spacing: 16)) : AnyLayout(VStackLayout(spacing: 22))
        ScrollView {
            layout {
                ZStack {
                    VFRing(parts: p.all, lineWidth: compact ? 10 : 18)
                    VStack(spacing: 2) {
                        Text(p.total, format: .percent.precision(.fractionLength(0))).font((compact ? Font.title2 : .largeTitle).bold().monospacedDigit())
                        Text("of the game").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(width: compact ? 120 : 240, height: compact ? 120 : 240)
                VStack(alignment: .leading, spacing: 10) {
                    stat(String(localized: "Missions"), p.missions, 0, detail: "\(content.missions.filter { progress.isDone($0) }.count)/\(content.missions.count)")
                    stat(String(localized: "Places"), p.places, 1, detail: "\(progress.data.visited.count)")
                    stat(String(localized: "Collectibles"), p.collectibles, 2, detail: "\(content.content.collectibles.reduce(0) { $0 + min($1.target, progress.found($1)) })/\(content.totalCollectibles)")
                    stat(String(localized: "Challenges"), p.challenges, 3, detail: "\(progress.data.challenges.count)/\(content.content.challenges.count)")
                    if !compact {
                        Button { share = true } label: { Label("Share as an image", systemImage: "square.and.arrow.up") }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 6)
                    }
                }
            }
            .padding(compact ? 12 : 30)
            .frame(maxWidth: .infinity)
        }
        .scrollDisabled(compact)
        .frame(height: compact ? 150 : nil)
        .background(compact ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 22))
        .navigationTitle(compact ? "" : String(localized: "Your 100%"))
        .sheet(isPresented: $share) { ShareProgressView() }
    }

    private func stat(_ name: String, _ v: Double, _ i: Int, detail: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(VF.ringColors[i]).frame(width: 10, height: 10)
            Text(name).font(compact ? .subheadline : .body)
            Spacer(minLength: 8)
            Text(detail).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Text(v, format: .percent.precision(.fractionLength(0))).font((compact ? Font.subheadline : .body).monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: compact ? .infinity : 360)
    }
}

struct MissionDetail: View {
    var mission: VFMission
    @Environment(ContentStore.self) private var content
    @Environment(Progress.self) private var progress
    @State private var revealed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let c = content.chapter(mission.chapter) {
                    Text(progress.hidden(mission.chapter) && !revealed ? String(localized: "Chapter \(c.id)") : c.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(VF.coral)
                }
                if progress.hidden(mission.chapter) && !revealed {
                    Text("Hidden mission").font(.largeTitle.bold())
                    SpoilerGate(chapter: mission.chapter) { revealed = true }
                } else {
                    Text(mission.title).font(.largeTitle.bold())
                    HStack(spacing: 14) {
                        if let g = mission.giver { Label(g, systemImage: "person.fill") }
                        if let l = mission.location { Label(l, systemImage: "mappin.and.ellipse") }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    if !mission.objectives.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Objectives").font(.headline).padding(.bottom, 8)
                            ForEach(Array(mission.objectives.enumerated()), id: \.offset) { i, o in
                                Button { progress.toggleObjective(mission, i) } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: progress.objectiveDone(mission, i) ? "checkmark.square.fill" : "square")
                                            .foregroundStyle(progress.objectiveDone(mission, i) ? VF.teal : .secondary)
                                        Text(o).foregroundStyle(.primary).strikethrough(progress.objectiveDone(mission, i))
                                        Spacer()
                                    }
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                        .background(.regularMaterial, in: .rect(cornerRadius: 18))
                    }
                    if let w = mission.walkthrough {
                        Text("Walkthrough").font(.headline)
                        MarkdownBlocks(text: w)
                    }
                    if let tips = mission.tips, !tips.isEmpty {
                        MarkdownBlocks(text: tips.map { "> " + $0 }.joined(separator: "\n"))
                    }
                    if let u = mission.unlocks {
                        Label(u, systemImage: "lock.open.fill").font(.subheadline).foregroundStyle(VF.teal)
                    }
                    MissionShots(mission: mission)
                }
                Button { progress.toggle(mission) } label: {
                    Label(progress.isDone(mission) ? "Completed" : "Mark as completed",
                          systemImage: progress.isDone(mission) ? "checkmark.circle.fill" : "circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(progress.isDone(mission) ? VF.teal : VF.coral)
                .padding(.top, 8)
            }
            .padding()
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Les objets à collectionner et le reste du 100 % : un compteur par série, rangé par groupe.
struct CollectibleRows: View {
    @Environment(ContentStore.self) private var content
    @Environment(Progress.self) private var progress

    var body: some View {
        let sets = content.content.collectibles
        let groups = sets.reduce(into: [String]()) { if let g = $1.group, !$0.contains(g) { $0.append(g) } }
        ForEach(groups.isEmpty ? [""] : groups, id: \.self) { g in
            Section {
                ForEach(sets.filter { ($0.group ?? "") == g }) { s in row(s) }
            } header: {
                if !g.isEmpty { Text(g) }
            }
        }
    }

    private func row(_ s: VFCollectibleSet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(s.title).font(.headline)
                Spacer()
                Stepper(value: Binding(get: { progress.found(s) }, set: { progress.setFound(s, $0) }), in: 0...s.count) {
                    Text("\(progress.found(s))/\(s.target)").monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                        .foregroundStyle(progress.found(s) >= s.target ? VF.teal : .primary)
                }
                .fixedSize()
            }
            ProgressView(value: Double(min(progress.found(s), s.target)), total: Double(max(1, s.target))).tint(progress.found(s) >= s.target ? VF.teal : VF.sun)
            if let sum = s.summary { Text(sum).font(.footnote).foregroundStyle(.secondary) }
            if let r = s.reward { Label(r, systemImage: "gift.fill").font(.footnote).foregroundStyle(VF.magenta) }
        }
        .padding(.vertical, 4)
    }
}

struct CollectiblesView: View {
    var body: some View {
        List { CollectibleRows() }.navigationTitle("Collectibles").scrollContentBackground(.hidden).background(VFBackdrop())
    }
}

/// L'image à partager : l'anneau, les quatre parts, le temps de jeu.
struct ShareProgressView: View {
    @Environment(ContentStore.self) private var content
    @Environment(Progress.self) private var progress
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var scale

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                card.frame(width: 340, height: 440).clipShape(.rect(cornerRadius: 28)).shadow(radius: 20, y: 8)
                if let img = render() {
                    ShareLink(item: Image(uiImage: img), preview: SharePreview(String(localized: "My Leonida progress"), image: Image(uiImage: img))) {
                        Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: 280)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    @MainActor private func render() -> UIImage? {
        let r = ImageRenderer(content: card.frame(width: 340, height: 440).environment(content).environment(progress))
        r.scale = max(3, scale)
        return r.uiImage
    }

    private var card: some View {
        let p = progress.parts(content.content)
        return ZStack {
            LinearGradient(colors: [VF.night, Color(red: 0.25, green: 0.08, blue: 0.25)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 18) {
                HStack {
                    Avatar(size: 40)
                    VStack(alignment: .leading) {
                        Text(progress.data.name.isEmpty ? String(localized: "My game") : progress.data.name).font(.headline)
                        if progress.hours > 0 { Text("\(Int(progress.hours)) h played").font(.caption).opacity(0.7) }
                    }
                    Spacer()
                }
                ZStack {
                    VFRing(parts: p.all, lineWidth: 14)
                    VStack(spacing: 0) {
                        Text(p.total, format: .percent.precision(.fractionLength(0))).font(.system(size: 44, weight: .heavy).monospacedDigit())
                        Text("of Leonida").font(.caption).opacity(0.7)
                    }
                }
                .frame(width: 210, height: 210)
                HStack(spacing: 14) {
                    mini("Missions", p.missions, 0); mini("Places", p.places, 1); mini("Items", p.collectibles, 2); mini("Challenges", p.challenges, 3)
                }
                Text("Vicefold").font(.caption.bold()).opacity(0.6)
            }
            .padding(24)
            .foregroundStyle(.white)
        }
    }

    private func mini(_ t: LocalizedStringKey, _ v: Double, _ i: Int) -> some View {
        VStack(spacing: 2) {
            Text(v, format: .percent.precision(.fractionLength(0))).font(.subheadline.bold().monospacedDigit()).foregroundStyle(VF.ringColors[i])
            Text(t).font(.caption2).opacity(0.75)
        }
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
            Text("My screenshots").font(.headline)
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
                            .foregroundStyle(VF.coral)
                            .background(VF.coral.opacity(0.12), in: .rect(cornerRadius: 12))
                        }
                    }
                }
            }
            Text("Take a screenshot in the game (PS5: Create button) and add it here to remember this mission. Touch and hold one to delete it.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
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
                Color.secondary.opacity(0.2)
            }
        }
        .frame(width: 120, height: 76)
        .clipShape(.rect(cornerRadius: 12))
    }

    private struct ShotName: Identifiable { var id: String }
}
