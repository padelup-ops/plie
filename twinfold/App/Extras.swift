// Extras.swift — Twinfold
//
// AI next to the page (ChatGPT, Claude or Gemini on their own sites, in the other pane, with the person's own
// account), reader view with read aloud, and saving a page as a PDF.

import AVFoundation
import NaturalLanguage
import SwiftUI
import WebKit

// MARK: - AI in the other pane

enum Assistant: String, CaseIterable, Identifiable {
    case chatGPT, claude, gemini
    var id: String { rawValue }

    var name: String {
        switch self {
        case .chatGPT: return "ChatGPT"
        case .claude: return "Claude"
        case .gemini: return "Gemini"
        }
    }

    var home: URL {
        switch self {
        case .chatGPT: return URL(string: "https://chatgpt.com/")!
        case .claude: return URL(string: "https://claude.ai/new")!
        case .gemini: return URL(string: "https://gemini.google.com/app")!
        }
    }

    /// The site with the question already typed in, when the site allows it. Gemini doesn't: the question is
    /// copied instead, ready to paste.
    func url(asking prompt: String) -> URL? {
        let q = prompt.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(["&", "+", "=", "?", "#"])) ?? ""
        switch self {
        case .chatGPT: return URL(string: "https://chatgpt.com/?q=\(q)")
        case .claude: return URL(string: "https://claude.ai/new?q=\(q)")
        case .gemini: return nil
        }
    }

    enum AITask: String, CaseIterable, Identifiable {
        case summarize, translate, explain
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .summarize: return "Summarize This Page"
            case .translate: return "Translate This Page"
            case .explain: return "Explain This Page Simply"
            }
        }

        func prompt(url: URL, title: String) -> String {
            let lang = Locale.current.localizedString(forLanguageCode: Locale.current.language.languageCode?.identifier ?? "en") ?? "English"
            switch self {
            case .summarize: return String(localized: "Summarize this page in a few bullet points: \(title) \(url.absoluteString)")
            case .translate: return String(localized: "Translate the main text of this page into \(lang): \(url.absoluteString)")
            case .explain: return String(localized: "Explain this page simply, as if to a friend: \(title) \(url.absoluteString)")
            }
        }
    }
}

extension Browser {
    /// Opens the assistant in the other pane (two pages side by side: the page, and the AI about it).
    func ask(_ assistant: Assistant, _ task: Assistant.AITask?) {
        let other = otherIndex
        guard let task, let tab = activeTab, let url = tab.url else {
            load(assistant.home, inPane: other)
            if !isSplit { toggleSplit() }
            return
        }
        let prompt = task.prompt(url: url, title: tab.title)
        if let direct = assistant.url(asking: prompt) {
            load(direct, inPane: other)
        } else {
            UIPasteboard.general.string = prompt
            load(assistant.home, inPane: other)
            flash(String(localized: "Question copied: paste it in \(assistant.name)"))
        }
        if !isSplit { toggleSplit() }
    }

    /// Saves the whole page as a PDF and offers to share or keep it.
    func sharePDF() {
        guard let tab = activeTab else { return }
        let name = (tab.title.isEmpty ? "Page" : tab.title).replacingOccurrences(of: "/", with: "-").prefix(60)
        tab.webView.createPDF { result in
            MainActor.assumeIsolated {
                guard case .success(let data) = result else {
                    self.flash(String(localized: "This page can't be saved as a PDF"))
                    return
                }
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).pdf")
                try? data.write(to: file)
                let share = UIActivityViewController(activityItems: [file], applicationActivities: nil)
                share.popoverPresentationController?.sourceView = tab.webView
                Tab.topController()?.present(share, animated: true)
            }
        }
    }
}

// MARK: - Reader view

struct Article: Equatable {
    var title: String
    var site: String
    var blocks: [Block]

    struct Block: Equatable, Identifiable {
        let id: Int
        let kind: String   // p, h, li, q
        let text: String
    }

    var plainText: String { ([title] + blocks.map(\.text)).joined(separator: "\n\n") }

    /// Finds the main text of the page: the block with the most paragraph text, its headings, lists and quotes.
    static let script = #"""
    (function () {
      var best = null, bestScore = 0;
      var cands = document.querySelectorAll('article, main, [role=main], .post, .entry-content, .article, .content, #content, section, div');
      for (var i = 0; i < cands.length && i < 3000; i++) {
        var el = cands[i], score = 0, ps = el.querySelectorAll(':scope > p, :scope > div > p, :scope > section > p');
        for (var j = 0; j < ps.length; j++) score += ps[j].innerText.length;
        if (el.tagName === 'ARTICLE' || el.tagName === 'MAIN') score *= 1.3;
        if (score > bestScore) { bestScore = score; best = el; }
      }
      if (!best || bestScore < 200) best = document.body;
      var out = [];
      var nodes = best.querySelectorAll('h1, h2, h3, h4, p, li, blockquote');
      for (var k = 0; k < nodes.length && out.length < 600; k++) {
        var n = nodes[k];
        if (n.closest('nav, footer, aside, form, header nav, [aria-hidden=true]')) continue;
        var t = (n.innerText || '').replace(/\s+/g, ' ').trim();
        if (t.length < 2) continue;
        var tag = n.tagName.toLowerCase();
        var kind = tag[0] === 'h' ? 'h' : (tag === 'li' ? 'li' : (tag === 'blockquote' ? 'q' : 'p'));
        if (kind === 'p' && t.length < 30 && n.querySelector('a')) continue;
        out.push([kind, t]);
      }
      var h1 = document.querySelector('h1');
      return JSON.stringify({ title: (h1 && h1.innerText.trim()) || document.title, blocks: out });
    })();
    """#

    @MainActor
    static func read(from tab: Tab) async -> Article? {
        guard let json = (try? await tab.webView.evaluateJavaScript(script)) as? String,
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let raw = obj["blocks"] as? [[String]] ?? []
        var blocks: [Block] = []
        for (i, b) in raw.enumerated() where b.count == 2 {
            // The title is shown on its own.
            if i == 0, b[0] == "h", b[1] == obj["title"] as? String { continue }
            blocks.append(Block(id: i, kind: b[0], text: b[1]))
        }
        guard blocks.count >= 2 else { return nil }
        return Article(title: obj["title"] as? String ?? tab.displayTitle, site: tab.displayAddress, blocks: blocks)
    }
}

@MainActor @Observable
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Speaker()
    private let synth = AVSpeechSynthesizer()
    private(set) var speaking = false

    override init() {
        super.init()
        synth.delegate = self
    }

    func toggle(_ text: String) {
        if speaking {
            synth.stopSpeaking(at: .immediate)
            speaking = false
            return
        }
        let u = AVSpeechUtterance(string: text)
        let rec = NLLanguageRecognizer()
        rec.processString(String(text.prefix(1000)))
        if let lang = rec.dominantLanguage?.rawValue { u.voice = AVSpeechSynthesisVoice(language: lang) }
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(u)
        speaking = true
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        speaking = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = false }
    }
}

struct ReaderSheet: View {
    @Environment(Browser.self) private var browser
    @Environment(\.dismiss) private var dismiss
    @State private var article: Article?
    @State private var failed = false
    @AppStorage("readerSize") private var size = 19.0
    @AppStorage("readerSerif") private var serif = true
    @AppStorage("readerTheme") private var theme = 0

    private var bg: Color { [Color(.systemBackground), Color(red: 0.98, green: 0.95, blue: 0.88), Color(red: 0.1, green: 0.11, blue: 0.12)][theme] }
    private var fg: Color { theme == 2 ? Color(white: 0.88) : (theme == 1 ? Color(red: 0.25, green: 0.2, blue: 0.14) : .primary) }

    var body: some View {
        NavigationStack {
            Group {
                if let article {
                    ScrollView {
                        VStack(alignment: .leading, spacing: size * 0.8) {
                            Text(article.site).font(.caption.weight(.semibold)).foregroundStyle(fg.opacity(0.6))
                            Text(article.title).font(.system(size: size * 1.45, weight: .bold, design: serif ? .serif : .default))
                            ForEach(article.blocks) { b in
                                switch b.kind {
                                case "h":
                                    Text(b.text).font(.system(size: size * 1.15, weight: .semibold, design: serif ? .serif : .default))
                                        .padding(.top, size * 0.4)
                                case "li":
                                    HStack(alignment: .firstTextBaseline, spacing: 8) { Text("•"); Text(b.text) }
                                        .font(.system(size: size, design: serif ? .serif : .default))
                                case "q":
                                    Text(b.text).italic().font(.system(size: size, design: serif ? .serif : .default))
                                        .padding(.leading, 14)
                                        .overlay(alignment: .leading) { Rectangle().fill(Brand.accent).frame(width: 3) }
                                default:
                                    Text(b.text).font(.system(size: size, design: serif ? .serif : .default))
                                        .lineSpacing(size * 0.35)
                                }
                            }
                        }
                        .foregroundStyle(fg)
                        .textSelection(.enabled)
                        .padding(22)
                        .frame(maxWidth: 680, alignment: .leading)
                        .frame(maxWidth: .infinity)
                    }
                } else if failed {
                    ContentUnavailableView("No Article Here", systemImage: "doc.plaintext",
                                           description: Text("Reader view works on pages with a main text, like articles and recipes."))
                } else {
                    ProgressView()
                }
            }
            .background(bg.ignoresSafeArea())
            .navigationTitle("Reader")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { Speaker.shared.toggle(article?.plainText ?? "") } label: {
                        Label(LocalizedStringKey(Speaker.shared.speaking ? "Stop Reading" : "Read Aloud"),
                              systemImage: Speaker.shared.speaking ? "stop.fill" : "play.fill")
                    }
                    .disabled(article == nil)
                    Spacer()
                    Menu {
                        Picker("Theme", selection: $theme) {
                            Text("Light").tag(0)
                            Text("Sepia").tag(1)
                            Text("Dark").tag(2)
                        }
                        Toggle("Serif Font", isOn: $serif)
                    } label: { Image(systemName: "paintpalette") }
                    Button { size = max(14, size - 2) } label: { Image(systemName: "textformat.size.smaller") }
                    Button { size = min(32, size + 2) } label: { Image(systemName: "textformat.size.larger") }
                }
            }
        }
        .task {
            guard let tab = browser.activeTab else { failed = true; return }
            article = await Article.read(from: tab)
            failed = article == nil
        }
        .onDisappear { Speaker.shared.stop() }
    }
}
