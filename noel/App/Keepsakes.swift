// Keepsakes.swift — Allô Père Noël
//
// La lettre du Père Noël et le certificat d'enfant sage, en PDF, et le filigrane des images partagées.
// Le prénom ne quitte l'iPhone que si le parent partage lui-même le fichier.

import SwiftUI
import UIKit

struct SharedKeepsake<Card: View>: View {
    var card: Card
    var body: some View {
        VStack(spacing: 10) {
            card
            Text("Allô Père Noël")
                .font(.ui(14, .bold))
                .foregroundStyle(Noel.cream)
            Text(NoelLinks.watermark)
                .font(.ui(11))
                .foregroundStyle(Noel.cream.opacity(0.7))
        }
        .padding(18)
        .background(Color(red: 0.05, green: 0.08, blue: 0.15))
    }
}

enum KeepsakePDF {
    static func letter(name: String, age: Int, qualities: [String]) -> URL? {
        write("lettre-pere-noel.pdf") { ctx, page in
            paper(ctx, page)
            draw(String(localized: "Letter from Santa"), at: CGPoint(x: 64, y: 86), size: 28, bold: true, ctx: ctx)
            let who = name.isEmpty ? String(localized: "my child") : name
            var body = String(localized: "Dear \(who),") + "\n\n"
            body += String(localized: "I am writing from my workshop at the North Pole. This year I heard about you, and I am proud of you.")
            if age > 0 {
                body += " " + String(localized: "You are \(age) years old, and that is a wonderful age.")
            }
            if !qualities.isEmpty {
                body += " " + String(localized: "I was told this about you: \(qualities.formatted(.list(type: .and))).")
            }
            body += "\n\n" + String(localized: "Be kind, keep wondering, and sleep well. I will be there on Christmas night.")
            body += "\n\n" + String(localized: "With all my love,\nSanta Claus")
            drawBlock(body, in: CGRect(x: 64, y: 140, width: page.width - 128, height: 560), ctx: ctx)
            footer(ctx, page)
        }
    }

    static func certificate(name: String, filename: String = "certificat-enfant-sage.pdf") -> URL? {
        write(filename) { ctx, page in
            paper(ctx, page)
            ctx.setStrokeColor(UIColor(red: 0.72, green: 0.54, blue: 0.22, alpha: 1).cgColor)
            ctx.setLineWidth(3)
            ctx.stroke(page.insetBy(dx: 28, dy: 28))
            ctx.setLineWidth(1)
            ctx.stroke(page.insetBy(dx: 36, dy: 36))
            draw(String(localized: "Good-child certificate"), at: CGPoint(x: 64, y: 120), size: 26, bold: true, ctx: ctx, center: page)
            let who = name.isEmpty ? String(localized: "my child") : name
            draw(who, at: CGPoint(x: 64, y: 250), size: 32, bold: true, ctx: ctx, center: page)
            let year = Calendar.current.component(.year, from: Date())
            drawBlock(String(localized: "Santa Claus certifies that this child has been kind, curious and full of heart in \(year)."),
                      in: CGRect(x: 80, y: 320, width: page.width - 160, height: 160), ctx: ctx, center: true)
            draw(String(localized: "The North Pole"), at: CGPoint(x: 64, y: 520), size: 16, bold: false, ctx: ctx, center: page)
            footer(ctx, page)
        }
    }

    private static func write(_ name: String, _ draw: (CGContext, CGRect) -> Void) -> URL? {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let data = UIGraphicsPDFRenderer(bounds: page).pdfData { renderer in
            renderer.beginPage()
            draw(renderer.cgContext, page)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try data.write(to: url) } catch { return nil }
        return url
    }

    private static func paper(_ ctx: CGContext, _ page: CGRect) {
        UIColor(red: 0.99, green: 0.96, blue: 0.90, alpha: 1).setFill()
        ctx.fill(page)
    }

    private static func footer(_ ctx: CGContext, _ page: CGRect) {
        let text = NoelLinks.watermark + "\n" + NoelLinks.storeSearch.absoluteString
        drawBlock(text, in: CGRect(x: 48, y: page.height - 78, width: page.width - 96, height: 48), ctx: ctx, center: true, size: 9, color: .darkGray)
    }

    private static func draw(_ text: String, at: CGPoint, size: CGFloat, bold: Bool, ctx: CGContext, center: CGRect? = nil) {
        let font = bold ? UIFont.systemFont(ofSize: size, weight: .bold) : UIFont.systemFont(ofSize: size)
        let style = NSMutableParagraphStyle()
        style.alignment = center == nil ? .left : .center
        let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(red: 0.28, green: 0.10, blue: 0.08, alpha: 1), .paragraphStyle: style]
        let width = center?.width ?? 480
        let origin = center.map { CGPoint(x: $0.minX + 40, y: at.y) } ?? at
        (text as NSString).draw(in: CGRect(x: origin.x, y: origin.y, width: (center?.width ?? width) - (center == nil ? 0 : 80), height: size * 2.2), withAttributes: attr)
    }

    private static func drawBlock(_ text: String, in rect: CGRect, ctx: CGContext, center: Bool = false, size: CGFloat = 15, color: UIColor = UIColor(red: 0.22, green: 0.12, blue: 0.10, alpha: 1)) {
        let style = NSMutableParagraphStyle()
        style.alignment = center ? .center : .left
        style.lineSpacing = 4
        let attr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size),
            .foregroundColor: color,
            .paragraphStyle: style
        ]
        (text as NSString).draw(in: rect, withAttributes: attr)
    }
}

struct LetterView: View {
    @Environment(AppModel.self) private var model
    @Environment(MagicStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var extraName = ""
    @State private var letter: URL?
    @State private var certificate: URL?
    @State private var extra: URL?
    @State private var gate = false

    private var childName: String { model.profile.cleanNames.formatted(.list(type: .and)) }
    private var qualities: [String] {
        model.profile.qualities.map { qualityName($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !store.owned {
                        Text("The letter and the certificate are part of the Christmas Pass.")
                            .font(.ui(16))
                            .foregroundStyle(Noel.cream.opacity(0.8))
                        Button { model.sheet = .paywall } label: { Text("Unlock the Christmas Pass") }
                            .buttonStyle(MagicButtonStyle())
                    } else {
                        Text("Print them, or share them. The child's name leaves this iPhone only if you share the file.")
                            .font(.ui(15))
                            .foregroundStyle(Noel.cream.opacity(0.75))
                        if let letter {
                            ShareLink(item: letter) { Label("Share the letter", systemImage: "envelope.fill") }
                                .buttonStyle(MagicButtonStyle())
                        }
                        if let certificate {
                            ShareLink(item: certificate) { Label("Share the certificate", systemImage: "rosette") }
                                .buttonStyle(QuietButtonStyle())
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("A message for another child")
                                .font(.ui(17, .bold))
                                .foregroundStyle(Noel.cream)
                            Text("Messages left: \(store.credits)")
                                .font(.ui(13))
                                .foregroundStyle(Noel.cream.opacity(0.6))
                            TextField("First name for this message", text: $extraName)
                                .textFieldStyle(.roundedBorder)
                            if let extra {
                                ShareLink(item: extra) { Label("Share this message", systemImage: "square.and.arrow.up") }
                                    .buttonStyle(QuietButtonStyle())
                            } else if store.credits > 0 {
                                Button { makeExtra() } label: { Text("Create the message") }
                                    .buttonStyle(QuietButtonStyle())
                                    .disabled(extraName.trimmingCharacters(in: .whitespaces).isEmpty)
                            } else {
                                Button { gate = true } label: { Text("3 extra messages for \(store.messagesPrice)") }
                                    .buttonStyle(QuietButtonStyle())
                            }
                        }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Noel.night.opacity(0.55)))
                    }
                }
                .padding(24)
            }
            .background(Color(red: 0.05, green: 0.08, blue: 0.15).ignoresSafeArea())
            .navigationTitle(Text("Letter from Santa"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task {
            guard store.owned else { return }
            let age = model.profile.isPlural ? 0 : model.profile.age
            letter = KeepsakePDF.letter(name: childName, age: age, qualities: qualities)
            certificate = KeepsakePDF.certificate(name: childName)
        }
        .sheet(isPresented: $gate) {
            ParentalGate {
                gate = false
                Task { await store.buyMessages() }
            }
            .presentationDetents([.medium])
            .preferredColorScheme(.dark)
        }
    }

    private func makeExtra() {
        let name = extraName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let url = KeepsakePDF.certificate(name: name, filename: "message-extra.pdf") else { return }
        guard store.spendCredit() else { return }
        extra = url
    }

    private func qualityName(_ q: Quality) -> String {
        switch q {
        case .kind: return String(localized: "Kind")
        case .curious: return String(localized: "Curious")
        case .brave: return String(localized: "Brave")
        case .funny: return String(localized: "Funny")
        case .sporty: return String(localized: "Sporty")
        case .dreamer: return String(localized: "Dreamer")
        case .creative: return String(localized: "Creative")
        case .caring: return String(localized: "Caring")
        case .adventurous: return String(localized: "Adventurous")
        }
    }
}
