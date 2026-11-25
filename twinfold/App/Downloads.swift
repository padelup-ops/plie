// Downloads.swift — Twinfold
//
// Files from the web, downloaded by the system rather than by the page: a background download session keeps going
// when Twinfold is left, put away or even closed by iOS, and a notification says when the file is there. Files land
// in Twinfold's folder in the Files app (On My iPhone › Twinfold › Downloads). Pages that build a file themselves
// (blob: and data: links, forms) are downloaded by WebKit instead, while Twinfold is open.

import QuickLook
import SwiftUI
import UserNotifications
import WebKit

@MainActor @Observable
final class Downloads: NSObject {
    static let shared = Downloads()
    static let sessionID = "com.padelup.twinfold.downloads"

    struct Item: Identifiable, Codable, Equatable {
        var id = UUID()
        var name: String
        var source: URL
        var file: URL?
        var received: Int64 = 0
        var expected: Int64 = 0
        var failed: String?
        var date = Date()
        var taskID: Int?

        var done: Bool { file != nil }
        var fraction: Double { expected > 0 ? min(1, Double(received) / Double(expected)) : 0 }
    }

    private(set) var items: [Item] = []
    /// Set by the system when it wakes Twinfold to finish a download in the background.
    var backgroundCompletion: (() -> Void)?

    @ObservationIgnored private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionID)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.allowsCellularAccess = true
        // A download that loses the network while Twinfold is away waits and continues, instead of failing.
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: DownloadsDelegate.shared, delegateQueue: .main)
    }()
    @ObservationIgnored private var webDownloads: [ObjectIdentifier: UUID] = [:]

    static var folder: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var listURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("downloads.json")
    }

    override private init() {
        super.init()
        if let data = try? Data(contentsOf: Self.listURL), let list = try? JSONDecoder().decode([Item].self, from: data) {
            items = list
        }
        _ = session   // reconnect to downloads that went on while Twinfold was closed
        session.getAllTasks { _ in }
    }

    /// The system calls this when a background download needs the app. It can arrive before or after the session
    /// says its events are finished; either order still tells iOS we are done.
    @ObservationIgnored private var backgroundEventsFinished = false
    var backgroundCompletion: (() -> Void)?

    func setBackgroundCompletion(_ completion: @escaping () -> Void) {
        backgroundCompletion = completion
        deliverBackgroundCompletionIfReady()
    }

    func noteBackgroundEventsFinished() {
        backgroundEventsFinished = true
        deliverBackgroundCompletionIfReady()
    }

    private func deliverBackgroundCompletionIfReady() {
        guard backgroundEventsFinished, let completion = backgroundCompletion else { return }
        backgroundCompletion = nil
        backgroundEventsFinished = false
        completion()
    }

    var active: Int { items.filter { !$0.done && $0.failed == nil }.count }

    // MARK: Starting

    /// A file the page links to: the system downloads it with the page's cookies, so it keeps going outside Twinfold.
    func start(_ request: URLRequest, suggested: String?, from webView: WKWebView) {
        Task {
            var req = request
            if let url = req.url {
                let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
                let mine = cookies.filter { c in
                    guard let host = url.host() else { return false }
                    let d = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain
                    return host == d || host.hasSuffix("." + d)
                }
                for (k, v) in HTTPCookie.requestHeaderFields(with: mine) { req.setValue(v, forHTTPHeaderField: k) }
            }
            let pageUA = (try? await webView.evaluateJavaScript("navigator.userAgent")) as? String
            if let ua = webView.customUserAgent ?? pageUA {
                req.setValue(ua, forHTTPHeaderField: "User-Agent")
            }
            if let page = webView.url { req.setValue(page.absoluteString, forHTTPHeaderField: "Referer") }
            let task = session.downloadTask(with: req)
            let name = suggested ?? Self.name(for: req.url)
            items.insert(Item(name: name, source: req.url ?? URL(string: "about:blank")!, taskID: task.taskIdentifier), at: 0)
            save()
            task.resume()
            askToNotify()
            Browser.shared.flash(String(localized: "Downloading \(name)"))
        }
    }

    /// Files a page makes itself (blob:, data:, a form's answer): WebKit downloads them, while Twinfold is open.
    func adopt(_ download: WKDownload) {
        download.delegate = DownloadsDelegate.shared
        let item = Item(name: Self.name(for: download.originalRequest?.url), source: download.originalRequest?.url ?? URL(string: "about:blank")!)
        webDownloads[ObjectIdentifier(download)] = item.id
        items.insert(item, at: 0)
        save()
    }

    // MARK: Progress (from the delegate)

    func progress(task: Int, received: Int64, expected: Int64) {
        guard let i = items.firstIndex(where: { $0.taskID == task && !$0.done }) else { return }
        items[i].received = received
        items[i].expected = expected
    }

    func finished(task: Int, at temp: URL, response: URLResponse?) {
        guard let i = items.firstIndex(where: { $0.taskID == task && !$0.done }) else { return }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            items[i].failed = HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            save()
            return
        }
        if let s = response?.suggestedFilename, !s.isEmpty, s != "Unknown" { items[i].name = s }
        let dest = Self.unique(items[i].name)
        do {
            try FileManager.default.moveItem(at: temp, to: dest)
            items[i].file = dest
            items[i].name = dest.lastPathComponent
            if items[i].expected <= 0 { items[i].expected = items[i].received }
            notify(items[i])
        } catch {
            items[i].failed = error.localizedDescription
        }
        save()
    }

    func failed(task: Int, error: Error) {
        guard let i = items.firstIndex(where: { $0.taskID == task && !$0.done }) else { return }
        if (error as NSError).code == NSURLErrorCancelled { items.remove(at: i) } else { items[i].failed = error.localizedDescription }
        save()
    }

    func webDestination(for download: WKDownload, suggested: String) -> URL {
        let dest = Self.unique(suggested)
        if let id = webDownloads[ObjectIdentifier(download)], let i = items.firstIndex(where: { $0.id == id }) {
            items[i].name = dest.lastPathComponent
            items[i].expected = download.progress.totalUnitCount
            observe(download, id: id, dest: dest)
        }
        return dest
    }

    func webFinished(_ download: WKDownload, error: Error?) {
        guard let id = webDownloads.removeValue(forKey: ObjectIdentifier(download)),
              let i = items.firstIndex(where: { $0.id == id }) else { return }
        if let error { items[i].failed = error.localizedDescription } else {
            items[i].file = Self.folder.appendingPathComponent(items[i].name)
            items[i].received = max(items[i].received, download.progress.completedUnitCount)
            items[i].expected = max(items[i].expected, items[i].received)
            notify(items[i])
        }
        save()
    }

    private func observe(_ download: WKDownload, id: UUID, dest: URL) {
        Task { [weak self] in
            while let self, self.webDownloads[ObjectIdentifier(download)] == id {
                if let i = self.items.firstIndex(where: { $0.id == id }) {
                    self.items[i].received = download.progress.completedUnitCount
                    self.items[i].expected = download.progress.totalUnitCount
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    // MARK: Managing

    func cancel(_ item: Item) {
        if let t = item.taskID {
            session.getAllTasks { tasks in tasks.first { $0.taskIdentifier == t }?.cancel() }
        }
        remove(item)
    }

    func remove(_ item: Item) {
        if let f = item.file { try? FileManager.default.removeItem(at: f) }
        items.removeAll { $0.id == item.id }
        save()
    }

    func clearFinished() {
        items.removeAll { $0.done || $0.failed != nil }
        save()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Self.listURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(items).write(to: Self.listURL, options: .atomic)
    }

    // MARK: Names and notifications

    static func name(for url: URL?) -> String {
        let last = url?.lastPathComponent ?? ""
        return last.isEmpty || last == "/" ? (url?.host() ?? "download") : last
    }

    static func unique(_ name: String) -> URL {
        let clean = name.replacingOccurrences(of: "/", with: "-")
        var url = folder.appendingPathComponent(clean)
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return url
    }

    private func askToNotify() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(_ item: Item) {
        guard UIApplication.shared.applicationState != .active else {
            Browser.shared.flash(String(localized: "Downloaded \(item.name)"))
            return
        }
        let c = UNMutableNotificationContent()
        c.title = String(localized: "Download finished")
        c.body = item.name
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: item.id.uuidString, content: c, trigger: nil))
    }
}

/// The download session's and WebKit's callbacks, passed on to `Downloads` on the main thread.
final class DownloadsDelegate: NSObject, URLSessionDownloadDelegate, WKDownloadDelegate, @unchecked Sendable {
    static let shared = DownloadsDelegate()

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let id = downloadTask.taskIdentifier
        MainActor.assumeIsolated { Downloads.shared.progress(task: id, received: totalBytesWritten, expected: totalBytesExpectedToWrite) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temporary file is gone as soon as this returns: move it aside first.
        let keep = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.moveItem(at: location, to: keep)
        let id = downloadTask.taskIdentifier, response = downloadTask.response
        MainActor.assumeIsolated { Downloads.shared.finished(task: id, at: keep, response: response) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let id = task.taskIdentifier
        MainActor.assumeIsolated { Downloads.shared.failed(task: id, error: error) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        MainActor.assumeIsolated { Downloads.shared.noteBackgroundEventsFinished() }
    }

    // WebKit
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        await MainActor.run { Downloads.shared.webDestination(for: download, suggested: suggestedFilename) }
    }

    func downloadDidFinish(_ download: WKDownload) {
        MainActor.assumeIsolated { Downloads.shared.webFinished(download, error: nil) }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        MainActor.assumeIsolated { Downloads.shared.webFinished(download, error: error) }
    }
}

// MARK: - The list

struct DownloadsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DownloadsList()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct DownloadsList: View {
    @State private var preview: URL?

    var body: some View {
        let d = Downloads.shared
        List {
            if d.items.isEmpty {
                ContentUnavailableView {
                    Label("No Downloads", systemImage: "arrow.down.circle")
                } description: {
                    Text("Files you download keep coming in even when you leave Twinfold. They're in the Files app too: On My iPhone › Twinfold › Downloads.")
                }
                .listRowBackground(Color.clear)
            }
            ForEach(d.items) { item in
                Button {
                    if let f = item.file { preview = f }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.failed != nil ? "exclamationmark.triangle.fill" : item.done ? "doc.fill" : "arrow.down.circle")
                            .font(.title3)
                            .foregroundStyle(item.failed != nil ? Brand.coral : Brand.accent)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                            if let f = item.failed {
                                Text(f).font(.caption).foregroundStyle(Brand.coral)
                            } else if item.done {
                                Text(ByteCountFormatter.string(fromByteCount: max(item.expected, item.received), countStyle: .file))
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                ProgressView(value: item.fraction).tint(Brand.accent)
                                Text(item.expected > 0
                                     ? "\(ByteCountFormatter.string(fromByteCount: item.received, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: item.expected, countStyle: .file))"
                                     : ByteCountFormatter.string(fromByteCount: item.received, countStyle: .file))
                                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                }
                .swipeActions {
                    if item.done || item.failed != nil {
                        Button("Delete", systemImage: "trash", role: .destructive) { d.remove(item) }
                    } else {
                        Button("Stop", systemImage: "stop.fill", role: .destructive) { d.cancel(item) }
                    }
                    if let f = item.file {
                        Button("Share", systemImage: "square.and.arrow.up") { Sharing.present([f]) }.tint(Brand.accent)
                    }
                }
            }
        }
        .navigationTitle("Downloads")
        .toolbar {
            if d.items.contains(where: { $0.done || $0.failed != nil }) {
                ToolbarItem(placement: .topBarLeading) { Button("Clear") { d.clearFinished() } }
            }
        }
        .quickLookPreview($preview)
    }
}
