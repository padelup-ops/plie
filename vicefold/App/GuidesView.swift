// GuidesView.swift — Vicefold
//
// Les guides par thème, et la lecture : sans spoiler par défaut (ce qui dépasse le chapitre où tu en es reste masqué,
// un toucher le révèle). Sur le Duo, la liste d'un côté du pli, le guide de l'autre.

import SwiftUI

struct GuidesView: View {
    @Environment(ContentStore.self) private var content
    @State private var selected: VFGuide?

    var body: some View {
        DualLayout {
            GuideList(selected: $selected)
        } secondary: {
            NavigationStack {
                if let g = selected { GuideReader(guide: g).id(g.id) } else { EmptyDetail(icon: "book.pages", text: "Pick a guide") }
            }
        }
        .onAppear {
            if ShotMode.route == "guide", selected == nil { selected = content.content.guides.first { $0.category != .start } ?? content.content.guides.first }
        }
    }
}

private struct GuideList: View {
    @Binding var selected: VFGuide?
    @Environment(\.vfWide) private var wide
    @Environment(ContentStore.self) private var content
    @Environment(Progress.self) private var progress
    @State private var push: VFGuide?

    var body: some View {
        NavigationStack {
            List {
                Group {
                    let all = content.content.guides
                    if all.isEmpty {
                        Section { VFEmptyState(icon: "book.pages", title: "No guides yet", message: "They arrive with a content update, no app update needed.").listRowBackground(Color.clear) }
                    } else {
                        Section { readCard(all) }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                    ForEach(VFGuideCategory.allCases) { cat in
                        let items = content.guides(cat)
                        if !items.isEmpty {
                            Section {
                                ForEach(items) { g in
                                    Button { open(g) } label: { row(g) }
                                        .buttonStyle(.plain)
                                        .listRowBackground(selected == g && wide ? VF.rowSelected : VF.row)
                                }
                            } header: {
                                Label(cat.title, systemImage: cat.icon)
                            }
                        }
                    }
                    Section {
                        NavigationLink { CheatsView() } label: { Label("Cheat codes", systemImage: "gamecontroller").foregroundStyle(VF.text) }
                        NavigationLink { CollectiblesView() } label: { Label("Collectibles checklist", systemImage: "sparkles").foregroundStyle(VF.text) }
                    }
                }
                .vfRows()
            }
            .navigationTitle("Guides")
            .vfScreen()
            .navigationDestination(item: $push) { GuideReader(guide: $0) }
            .refreshable { _ = await content.refresh() }
        }
    }

    /// Où tu en es dans la lecture : « 3/9 guides lus ».
    private func readCard(_ all: [VFGuide]) -> some View {
        let read = all.filter { progress.data.readGuides.contains($0.id) }.count
        return HStack(spacing: 14) {
            VFIconBadge(icon: "book.pages.fill", color: VF.sun, size: 44)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Guides read").font(.subheadline.weight(.semibold)).foregroundStyle(VF.text)
                    Spacer()
                    Text(verbatim: "\(read)/\(all.count)").font(VF.mono(12, weight: .bold)).foregroundStyle(VF.sun)
                }
                VFBar(value: Double(read) / Double(max(1, all.count)), color: VF.sun, gradient: false, height: 4)
            }
        }
        .vfCard(radius: 20, padding: 14)
        .accessibilityElement(children: .combine)
    }

    private func open(_ g: VFGuide) {
        if wide { selected = g } else { push = g }
    }

    private func row(_ g: VFGuide) -> some View {
        let read = progress.data.readGuides.contains(g.id)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(g.title).font(.body.weight(.semibold)).foregroundStyle(VF.text)
                if let s = g.summary { Text(s).font(.footnote).foregroundStyle(VF.textDim).lineLimit(2) }
                if let m = g.minutes { Text("\(m) min read").font(VF.mono(9.5)).textCase(.uppercase).foregroundStyle(VF.cyan) }
            }
            Spacer(minLength: 6)
            if progress.hidden(g.spoiler) { Image(systemName: "eye.slash").foregroundStyle(VF.textDim).font(.footnote).accessibilityLabel("Spoiler-free") }
            if read { Image(systemName: "checkmark.circle.fill").foregroundStyle(VF.palm).shadow(color: VF.palm.opacity(0.6), radius: 4).accessibilityLabel("Read") }
            if !wide { Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(VF.textFaint) }
        }
        .contentShape(.rect)
    }
}

struct GuideReader: View {
    var guide: VFGuide
    @Environment(Progress.self) private var progress
    @State private var revealed = false

    var body: some View {
        let read = progress.data.readGuides.contains(guide.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: guide.category.icon).font(.caption.weight(.bold)).foregroundStyle(VF.cyan)
                    Text(verbatim: guide.category.title).vfHUD(VF.cyan, size: 11)
                    if let m = guide.minutes { Text("· \(m) min").vfHUD(VF.textDim, size: 11) }
                }
                Text(guide.title).font(VF.display(38)).foregroundStyle(VF.text).fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let s = guide.summary { Text(s).font(.title3).foregroundStyle(VF.textDim) }
                Rectangle().fill(VF.gradient).frame(height: 2).shadow(color: VF.flamingo.opacity(0.7), radius: 5).accessibilityHidden(true)
                if progress.hidden(guide.spoiler) && !revealed {
                    SpoilerGate(chapter: guide.spoiler ?? 0) { revealed = true }
                } else {
                    MarkdownBlocks(text: guide.body)
                }
                Button {
                    progress.edit { d in
                        if d.readGuides.contains(guide.id) { d.readGuides.remove(guide.id) } else { d.readGuides.insert(guide.id) }
                    }
                } label: {
                    Label(read ? "Read" : "Mark as read", systemImage: read ? "checkmark.circle.fill" : "circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.vf(read ? .done : .primary))
                .padding(.top, 10)
            }
            .padding()
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(VFBackdrop())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: "\(guide.title)\n\n\(guide.summary ?? "")\n\n— Vicefold")
            }
        }
        .onAppear { Recents.shared.opened(.guide, guide.id) }
    }
}

/// Le texte des guides : titres (#), listes (-), étapes (1.), conseils (>), paragraphes, gras et liens en Markdown.
struct MarkdownBlocks: View {
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                switch b {
                case .heading(let t):
                    Text(md(t)).font(VF.display(22, relativeTo: .title3)).foregroundStyle(VF.text).padding(.top, 8)
                        .accessibilityAddTraits(.isHeader)
                case .bullet(let t):
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(VF.flamingo).frame(width: 6, height: 6).shadow(color: VF.flamingo, radius: 4)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        Text(md(t)).foregroundStyle(VF.text)
                    }
                case .step(let n, let t):
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(verbatim: "\(n)").font(VF.mono(11, weight: .bold)).foregroundStyle(VF.ink).frame(width: 22, height: 22).background(VF.gradient, in: .circle)
                        Text(md(t)).foregroundStyle(VF.text)
                    }
                case .tip(let t):
                    Label { Text(md(t)).foregroundStyle(VF.text) } icon: { Image(systemName: "lightbulb.fill").foregroundStyle(VF.sun).shadow(color: VF.sun.opacity(0.7), radius: 5) }
                        .vfCard(radius: 14, padding: 12, tint: VF.sun)
                case .para(let t): Text(md(t)).foregroundStyle(VF.text)
                }
            }
        }
        .lineSpacing(3)
        .tint(VF.cyan)
        .textSelection(.enabled)
    }

    enum Block { case heading(String), bullet(String), step(Int, String), tip(String), para(String) }

    private var blocks: [Block] {
        text.components(separatedBy: "\n").compactMap { raw in
            let l = raw.trimmingCharacters(in: .whitespaces)
            if l.isEmpty { return nil }
            if l.hasPrefix("#") { return .heading(l.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)) }
            if l.hasPrefix("- ") || l.hasPrefix("* ") { return .bullet(String(l.dropFirst(2))) }
            if l.hasPrefix("> ") { return .tip(String(l.dropFirst(2))) }
            if let dot = l.firstIndex(of: "."), let n = Int(l[..<dot]), l[l.index(after: dot)...].hasPrefix(" ") {
                return .step(n, String(l[l.index(dot, offsetBy: 2)...]))
            }
            return .para(l)
        }
    }

    private func md(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

struct SpoilerGate: View {
    var chapter: Int
    var reveal: () -> Void
    @Environment(ContentStore.self) private var content

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "eye.slash.fill").font(.system(size: 26, weight: .semibold)).foregroundStyle(VF.flamingo)
                .frame(width: 64, height: 64)
                .background(VF.flamingo.opacity(0.12), in: .circle)
                .overlay(Circle().stroke(VF.flamingo.opacity(0.55), lineWidth: 1))
                .shadow(color: VF.flamingo.opacity(0.5), radius: 10)
                .accessibilityHidden(true)
            Text("Spoiler-free").font(VF.display(24, relativeTo: .title2)).foregroundStyle(VF.text)
            // Le titre du chapitre masqué reste masqué : on n'en donne que le numéro.
            Text("This part talks about \(String(localized: "Chapter \(chapter)")). It stays hidden until you get there.")
                .font(.subheadline)
                .foregroundStyle(VF.textDim)
                .multilineTextAlignment(.center)
            Button("Show anyway", action: reveal).buttonStyle(.vf(.secondary, compact: true))
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .vfCard(radius: 20, padding: 18, tint: VF.flamingo)
    }
}
