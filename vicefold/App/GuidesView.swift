// GuidesView.swift — Vicefold
//
// Les guides par thème, et la lecture : sans spoiler par défaut (ce qui dépasse le chapitre où tu en es reste flou,
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
                ForEach(VFGuideCategory.allCases) { cat in
                    let items = content.guides(cat)
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { g in
                                Button { open(g) } label: { row(g) }
                                    .listRowBackground(selected == g && wide ? VF.coral.opacity(0.15) : nil)
                            }
                        } header: {
                            Label(cat.title, systemImage: cat.icon)
                        }
                    }
                }
                Section {
                    NavigationLink { CheatsView() } label: { Label("Cheat codes", systemImage: "gamecontroller") }
                    NavigationLink { CollectiblesView() } label: { Label("Collectibles checklist", systemImage: "sparkles") }
                }
            }
            .navigationTitle("Guides")
            .navigationDestination(item: $push) { GuideReader(guide: $0) }
        }
    }

    private func open(_ g: VFGuide) {
        if wide { selected = g } else { push = g }
    }

    private func row(_ g: VFGuide) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(g.title).foregroundStyle(.primary)
                if let s = g.summary { Text(s).font(.footnote).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer()
            if progress.hidden(g.spoiler) { Image(systemName: "eye.slash").foregroundStyle(.secondary).font(.footnote) }
            if progress.data.readGuides.contains(g.id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(VF.teal) }
        }
        .contentShape(.rect)
    }
}

struct GuideReader: View {
    var guide: VFGuide
    @Environment(Progress.self) private var progress
    @State private var revealed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Label(guide.category.title, systemImage: guide.category.icon)
                    if let m = guide.minutes { Text("· \(m) min") }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(VF.coral)
                Text(guide.title).font(.largeTitle.bold())
                if let s = guide.summary { Text(s).font(.title3).foregroundStyle(.secondary) }
                Divider()
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
                    Label(progress.data.readGuides.contains(guide.id) ? "Read" : "Mark as read",
                          systemImage: progress.data.readGuides.contains(guide.id) ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.bordered)
                .padding(.top, 10)
            }
            .padding()
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: "\(guide.title)\n\n\(guide.summary ?? "")\n\n— Vicefold")
            }
        }
    }
}

/// Le texte des guides : titres (#), listes (-), paragraphes, gras et liens en Markdown.
struct MarkdownBlocks: View {
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                switch b {
                case .heading(let t): Text(md(t)).font(.title3.bold()).padding(.top, 6)
                case .bullet(let t):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(VF.coral).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        Text(md(t))
                    }
                case .step(let n, let t):
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(n)").font(.footnote.bold()).foregroundStyle(.white).frame(width: 22, height: 22).background(VF.coral, in: .circle)
                        Text(md(t))
                    }
                case .tip(let t):
                    Label { Text(md(t)) } icon: { Image(systemName: "lightbulb.fill").foregroundStyle(VF.sun) }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(VF.sun.opacity(0.12), in: .rect(cornerRadius: 14))
                case .para(let t): Text(md(t))
                }
            }
        }
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
            Image(systemName: "eye.slash.circle.fill").font(.system(size: 44)).foregroundStyle(VF.magenta)
            Text("Spoiler-free").font(.headline)
            Text("This part talks about \(content.chapter(chapter)?.title ?? String(localized: "a later chapter")). It stays hidden until you get there.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Show anyway", action: reveal).buttonStyle(.bordered)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
    }
}
