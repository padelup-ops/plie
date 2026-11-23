// HomeView.swift — Vicefold
//
// L'accueil : ton 100 % en un anneau, la prochaine mission, par où commencer, et les nouveautés du guide.

import SwiftUI

struct HomeView: View {
    @Binding var tab: AppTab
    @Environment(ContentStore.self) private var content
    @Environment(Progress.self) private var progress
    @Environment(Store.self) private var store
    @State private var showShare = false
    @State private var showProfile = false

    var body: some View {
        DualLayout {
            // Gauche (ou tout, sur iPhone) : toi, ton 100 %, la suite.
            column(wideRight: false)
        } secondary: {
            // Droite du pli : par où commencer, les raccourcis, les nouveautés.
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        startHere
                        shortcuts
                        if let news = content.content.news, !news.isEmpty { newsCard(news) }
                        credits
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 20)
                }
                .background(backdrop)
            }
        }
        .sheet(isPresented: $showShare) { ShareProgressView() }
        .sheet(isPresented: $showProfile) { NavigationStack { ProfileView() } }
    }

    private func column(wideRight: Bool) -> some View {
        NavigationStack {
            WideReader { wide in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        ringCard
                        if let m = progress.nextMission(content.content) { nextCard(m) }
                        if !wide {
                            startHere
                            shortcuts
                            if let news = content.content.news, !news.isEmpty { newsCard(news) }
                            credits
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 30)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(backdrop)
            .navigationTitle(Self.appName)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showProfile = true } label: { Avatar(size: 32) }
                        .accessibilityLabel("Profile")
                }
            }
            .refreshable { _ = await content.refresh() }
        }
    }

    static var appName: String {
        Bundle.main.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? "GTA 6 Guide"
    }

    private var backdrop: some View {
        LinearGradient(colors: [VF.coral.opacity(0.22), VF.magenta.opacity(0.08), .clear], startPoint: .top, endPoint: .center)
            .ignoresSafeArea()
    }

    private var header: some View {
        let days = Calendar.current.dateComponents([.day], from: VF.release, to: Date()).day ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            Text(greeting).font(.title2.bold())
            Group {
                if days < 0 {
                    Text("Release in \(-days) days")
                } else if days == 0 {
                    Text("Out today on PS5 and Xbox Series")
                } else {
                    Text("Day \(days + 1) in Leonida")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 6)
    }

    private var greeting: String {
        let n = progress.data.name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? String(localized: "Welcome to Leonida") : String(localized: "Hi \(n)")
    }

    private var ringCard: some View {
        let p = progress.parts(content.content)
        return HStack(spacing: 18) {
            ZStack {
                VFRing(parts: p.all, lineWidth: 11)
                VStack(spacing: 0) {
                    Text(p.total, format: .percent.precision(.fractionLength(0)))
                        .font(.title2.bold().monospacedDigit())
                    Text("complete").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 132, height: 132)
            VStack(alignment: .leading, spacing: 8) {
                legend(String(localized: "Missions"), p.missions, 0)
                legend(String(localized: "Places"), p.places, 1)
                legend(String(localized: "Collectibles"), p.collectibles, 2)
                legend(String(localized: "Challenges"), p.challenges, 3)
                Button { showShare = true } label: {
                    Label("Share", systemImage: "square.and.arrow.up").font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .padding(.top, 2)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
        .onTapGesture { tab = .tracker }
    }

    private func legend(_ name: String, _ v: Double, _ i: Int) -> some View {
        HStack(spacing: 8) {
            Circle().fill(VF.ringColors[i]).frame(width: 9, height: 9)
            Text(name).font(.subheadline)
            Spacer(minLength: 4)
            Text(v, format: .percent.precision(.fractionLength(0))).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func nextCard(_ m: VFMission) -> some View {
        let hidden = progress.hidden(m.chapter)
        return NavigationLink {
            MissionDetail(mission: m)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "flag.checkered")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(VF.gradient, in: .rect(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Next mission").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(hidden ? String(localized: "Hidden until you get there") : m.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let c = content.chapter(m.chapter) {
                        Text(c.title).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding()
            .background(.regularMaterial, in: .rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    private var startHere: some View {
        let g = content.guides(.start)
        return VStack(alignment: .leading, spacing: 10) {
            if !g.isEmpty {
                Text("Start here").font(.title3.bold())
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(g) { guide in
                            NavigationLink { GuideReader(guide: guide) } label: { GuideCard(guide: guide) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    private var shortcuts: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            shortcut("Map of Leonida", "map.fill", VF.teal) { tab = .map }
            shortcut("Collectibles", "sparkles", VF.sun) { tab = .tracker }
            NavigationLink { CheatsView() } label: { tile("Cheat codes", "gamecontroller.fill", VF.magenta) }.buttonStyle(.plain)
            NavigationLink { RadioView() } label: { tile("Radio", "radio.fill", VF.coral) }.buttonStyle(.plain)
        }
    }

    private func shortcut(_ t: LocalizedStringKey, _ icon: String, _ c: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { tile(t, icon, c) }.buttonStyle(.plain)
    }

    private func tile(_ t: LocalizedStringKey, _ icon: String, _ c: Color) -> some View {
        HStack {
            Image(systemName: icon).font(.title3).foregroundStyle(c)
            Text(t).font(.subheadline.weight(.semibold))
            Spacer()
        }
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
    }

    private func newsCard(_ news: [VFNews]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What's new in the guide").font(.title3.bold())
            ForEach(news.prefix(3)) { n in
                VStack(alignment: .leading, spacing: 4) {
                    Text(n.title).font(.headline)
                    Text(n.body).font(.subheadline).foregroundStyle(.secondary)
                    Text(n.date).font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.regularMaterial, in: .rect(cornerRadius: 18))
            }
        }
    }

    private var credits: some View {
        Text("Unofficial fan guide. Not affiliated with, endorsed or approved by Rockstar Games or Take-Two Interactive. Game names are trademarks of their owners.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.top, 8)
    }
}

/// Lit « la page est en deux moitiés » à l'intérieur d'une pile de navigation.
struct WideReader<Content: View>: View {
    @Environment(\.vfWide) private var wide
    @ViewBuilder var content: (Bool) -> Content
    var body: some View { content(wide) }
}

struct GuideCard: View {
    var guide: VFGuide
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: guide.category.icon)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(VF.gradient, in: .rect(cornerRadius: 12))
            Text(guide.title).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
            if let s = guide.summary { Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(width: 210, height: 190, alignment: .topLeading)
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
    }
}

struct Avatar: View {
    var size: CGFloat
    @Environment(Progress.self) private var progress

    var body: some View {
        Group {
            if let img = UIImage(contentsOfFile: progress.photoURL.path) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Text(initial)
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(VF.gradient)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initial: String {
        progress.data.name.first.map { String($0).uppercased() } ?? "V"
    }
}
