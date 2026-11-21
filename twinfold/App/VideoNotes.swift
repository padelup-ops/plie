// VideoNotes.swift — Twinfold
//
// Notes that know the time: a video plays in one pane, the other pane becomes a notebook. Each note keeps the
// moment of the video it was written at; tap it and the video jumps back there. Notes are kept per video, on the
// iPhone. And hands-free reading: the page scrolls by itself, at the speed you set.

import SwiftUI
import WebKit

struct VideoNote: Codable, Identifiable, Hashable {
    var id = UUID()
    var time: Double
    var text: String
}

@MainActor @Observable
final class VideoNotes {
    static let shared = VideoNotes()
    private(set) var byVideo: [String: [VideoNote]] = [:]

    private init() {
        if let data = try? Data(contentsOf: Self.file), let d = try? JSONDecoder().decode([String: [VideoNote]].self, from: data) {
            byVideo = d
        }
    }

    private static var file: URL { Library.folder.appendingPathComponent("videonotes.json") }

    /// A video's key: its address without the time and tracking parts.
    static func key(_ url: URL?) -> String? {
        guard let url, var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        c.queryItems = c.queryItems?.filter { ["v", "id", "list"].contains($0.name) }
        if c.queryItems?.isEmpty == true { c.queryItems = nil }
        c.fragment = nil
        return c.url?.absoluteString
    }

    func notes(for url: URL?) -> [VideoNote] { Self.key(url).flatMap { byVideo[$0] } ?? [] }

    func add(_ text: String, at time: Double, for url: URL?) {
        guard let k = Self.key(url), !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        byVideo[k, default: []].append(VideoNote(time: time, text: text))
        byVideo[k]?.sort { $0.time < $1.time }
        save()
    }

    func delete(_ note: VideoNote, for url: URL?) {
        guard let k = Self.key(url) else { return }
        byVideo[k]?.removeAll { $0.id == note.id }
        save()
    }

    /// All the notes of a video, as text with times (to share or copy).
    func export(for url: URL?, title: String) -> String {
        ([title, url?.absoluteString ?? ""] + notes(for: url).map { "\(Self.clock($0.time))  \($0.text)" }).joined(separator: "\n")
    }

    private func save() {
        guard ShotMode.current == nil, let data = try? JSONEncoder().encode(byVideo) else { return }
        try? data.write(to: Self.file, options: .atomic)
    }

    static func clock(_ t: Double) -> String {
        let s = Int(t.rounded(.down))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

extension Tab {
    /// The time of the page's main video (the playing one, or the largest), in seconds.
    func videoTime() async -> Double? {
        let js = """
        (function(){var vs=Array.prototype.slice.call(document.querySelectorAll('video'));
        var v=vs.filter(function(x){return !x.paused;})[0]||vs.sort(function(a,b){return b.clientWidth*b.clientHeight-a.clientWidth*a.clientHeight;})[0];
        return v?v.currentTime:null;})()
        """
        return (try? await webView.evaluateJavaScript(js)) as? Double
    }

    func seekVideo(to t: Double) {
        let js = """
        (function(){var vs=Array.prototype.slice.call(document.querySelectorAll('video'));
        var v=vs.filter(function(x){return !x.paused;})[0]||vs.sort(function(a,b){return b.clientWidth*b.clientHeight-a.clientWidth*a.clientHeight;})[0];
        if(v){v.currentTime=\(t);v.play();}})()
        """
        webView.evaluateJavaScript(js)
    }

    // MARK: Hands-free reading

    /// Scrolls the page by itself (0 stops). Speed in points per second.
    func autoScroll(_ speed: Double) {
        let js = speed <= 0
            ? "if(window.__tfScroll){clearInterval(window.__tfScroll);window.__tfScroll=null;}"
            : "if(window.__tfScroll){clearInterval(window.__tfScroll);}window.__tfAcc=0;window.__tfScroll=setInterval(function(){window.__tfAcc+=\(speed)/60;var d=Math.floor(window.__tfAcc);if(d>0){window.__tfAcc-=d;window.scrollBy(0,d);}if(window.innerHeight+window.scrollY>=document.documentElement.scrollHeight-2){clearInterval(window.__tfScroll);window.__tfScroll=null;}},16);"
        webView.evaluateJavaScript(js)
        autoScrollSpeed = speed
    }
}

/// The notebook pane: notes timed to the video playing in the other pane.
struct VideoNotesPane: View {
    @Environment(Browser.self) private var browser
    let pane: Int
    @State private var draft = ""
    @State private var stamp: Double?
    @FocusState private var focused: Bool

    private var videoTab: Tab? { browser.panes[1 - pane].tab }

    var body: some View {
        let notes = VideoNotes.shared.notes(for: videoTab?.url)
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "note.text").font(.title3).foregroundStyle(Brand.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Video Notes").font(.headline)
                    Text(videoTab?.displayTitle ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if !notes.isEmpty, let tab = videoTab {
                    ShareLink(item: VideoNotes.shared.export(for: tab.url, title: tab.displayTitle)) {
                        Image(systemName: "square.and.arrow.up").frame(width: 36, height: 36)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                }
                Button { browser.closeTool(in: pane) } label: {
                    Image(systemName: "xmark").font(.footnote.weight(.bold)).frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel(Text("Close"))
            }
            .padding(14)

            if notes.isEmpty {
                ContentUnavailableView("Notes at the right moment", systemImage: "clock.badge",
                                       description: Text("Play a video in the other pane, write here: each note keeps its moment. Tap a note to jump back to it."))
            } else {
                List {
                    ForEach(notes) { note in
                        Button { videoTab?.seekVideo(to: note.time) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(VideoNotes.clock(note.time))
                                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                                    .foregroundStyle(Brand.accent)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Brand.accent.opacity(0.12), in: Capsule())
                                Text(note.text)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions { Button("Delete", role: .destructive) { VideoNotes.shared.delete(note, for: videoTab?.url) } }
                    }
                }
                .listStyle(.plain)
            }

            HStack(spacing: 8) {
                Text(stamp.map(VideoNotes.clock) ?? "–:––")
                    .font(.system(.footnote, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Brand.accent)
                TextField("Write a note…", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($focused)
                    .onChange(of: focused) { _, on in if on { Task { stamp = await videoTab?.videoTime() } } }
                    .onSubmit(add)
                Button(action: add) {
                    Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold)).frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(Brand.accent).interactive(), in: .circle)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel(Text("Add Note"))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
            .padding(12)
        }
        .background(Color(.systemBackground))
    }

    private func add() {
        let text = draft
        Task {
            var t = stamp ?? 0
            if stamp == nil, let now = await videoTab?.videoTime() { t = now }
            VideoNotes.shared.add(text, at: t, for: videoTab?.url)
            draft = ""
            stamp = await videoTab?.videoTime()
        }
    }
}

/// Speed buttons while the page scrolls by itself.
struct AutoScrollControls: View {
    let tab: Tab

    var body: some View {
        HStack(spacing: 4) {
            Button { tab.autoScroll(max(10, tab.autoScrollSpeed / 1.5)) } label: { Image(systemName: "tortoise.fill").frame(width: 40, height: 40) }
            Text("\(Int(tab.autoScrollSpeed))").font(.system(.caption, design: .rounded).weight(.bold)).monospacedDigit().frame(minWidth: 28)
            Button { tab.autoScroll(min(400, tab.autoScrollSpeed * 1.5)) } label: { Image(systemName: "hare.fill").frame(width: 40, height: 40) }
            Button { tab.autoScroll(0) } label: { Image(systemName: "stop.fill").frame(width: 40, height: 40) }
                .accessibilityLabel(Text("Stop Scrolling"))
        }
        .font(.system(size: 15, weight: .semibold))
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}
