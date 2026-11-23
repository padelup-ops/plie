// GameServer.swift — Hexfold
//
// Un serveur HTTP minimal sur 127.0.0.1 (port fixe : l'origine des parties enregistrées ne change pas) qui sert les
// fichiers du jeu embarqués dans l'app. Seulement en local : rien n'est accessible depuis le réseau.

import Foundation
import Network
import UniformTypeIdentifiers

final class GameServer: @unchecked Sendable {
    static let shared = GameServer()
    static let port: UInt16 = 47_811

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "hexfold.server", qos: .userInitiated)
    private let root = Bundle.main.url(forResource: "Game", withExtension: nil)!

    var baseURL: URL { URL(string: "http://127.0.0.1:\(Self.port)/index.html")! }

    func start() {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
        params.allowLocalEndpointReuse = true
        guard let l = try? NWListener(using: params) else { return }
        l.newConnectionHandler = { [weak self] c in self?.handle(c) }
        l.start(queue: queue)
        listener = l
    }

    private func handle(_ c: NWConnection) {
        c.start(queue: queue)
        receive(c, buffer: Data())
    }

    private func receive(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, done, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            if let end = buf.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buf[..<end.lowerBound], as: UTF8.self)
                self.respond(c, head: head)
            } else if error == nil && !done && buf.count < 256 * 1024 {
                self.receive(c, buffer: buf)
            } else {
                c.cancel()
            }
        }
    }

    private func respond(_ c: NWConnection, head: String) {
        let first = head.split(separator: "\r\n").first.map(String.init) ?? ""
        let parts = first.split(separator: " ")
        var path = parts.count >= 2 ? String(parts[1]) : "/"
        if let q = path.firstIndex(where: { $0 == "?" || $0 == "#" }) { path = String(path[..<q]) }
        path = path.removingPercentEncoding ?? path
        if path.hasSuffix("/") { path += "index.html" }
        let file = root.appendingPathComponent(String(path.drop(while: { $0 == "/" }))).standardizedFileURL
        let isHead = parts.first == "HEAD"
        guard file.path.hasPrefix(root.standardizedFileURL.path), let data = try? Data(contentsOf: file, options: .mappedIfSafe) else {
            send(c, status: "404 Not Found", type: "text/plain", body: Data("not found".utf8), head: isHead)
            return
        }
        // Les plages (sons et musiques lus par morceaux).
        if let r = head.range(of: "Range: bytes=", options: .caseInsensitive) {
            let spec = head[r.upperBound...].prefix { $0 != "\r" }
            let nums = spec.split(separator: "-", omittingEmptySubsequences: false)
            let a = Int(nums.first ?? "") ?? 0
            let b = nums.count > 1 && !nums[1].isEmpty ? min(Int(nums[1]) ?? data.count - 1, data.count - 1) : data.count - 1
            if a <= b, a < data.count {
                send(c, status: "206 Partial Content", type: mime(file), body: data.subdata(in: a..<(b + 1)), head: isHead,
                     extra: "Content-Range: bytes \(a)-\(b)/\(data.count)\r\n")
                return
            }
        }
        send(c, status: "200 OK", type: mime(file), body: data, head: isHead)
    }

    private func send(_ c: NWConnection, status: String, type: String, body: Data, head: Bool, extra: String = "") {
        var h = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nAccept-Ranges: bytes\r\n"
        h += "Cache-Control: no-cache\r\nConnection: close\r\n\(extra)\r\n"
        var out = Data(h.utf8)
        if !head { out.append(body) }
        c.send(content: out, completion: .contentProcessed { _ in c.cancel() })
    }

    private func mime(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js": return "text/javascript; charset=utf-8"
        case "json", "map": return "application/json"
        case "css": return "text/css"
        case "wasm": return "application/wasm"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "mp3": return "audio/mpeg"
        case "ogg": return "audio/ogg"
        case "txt", "atlas", "properties": return "text/plain; charset=utf-8"
        case "ttf": return "font/ttf"
        default: return UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        }
    }
}
