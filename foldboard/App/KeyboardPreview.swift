import SwiftUI
import UIKit

/// Le vrai clavier Foldboard, dans l'app : pour voir les réglages et les essayer.
struct KeyboardPreview: UIViewRepresentable {
    var settings: KBSettings
    var pro: Bool
    @Binding var text: String
    var onSettings: (KBSettings) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> KeyboardCanvas {
        let c = KeyboardCanvas()
        c.input = context.coordinator
        c.configure(settings: settings, pro: pro)
        c.appeared()
        return c
    }

    func updateUIView(_ view: KeyboardCanvas, context: Context) {
        context.coordinator.parent = self
        if view.settings != settings || view.pro != pro {
            view.configure(settings: settings, pro: pro)
        }
    }

    static func dismantleUIView(_ uiView: KeyboardCanvas, coordinator: Coordinator) {
        uiView.disappeared()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: KeyboardCanvas, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 390, height: uiView.preferredHeight)
    }

    final class Coordinator: KBInput {
        var parent: KeyboardPreview
        init(_ p: KeyboardPreview) { parent = p }

        func kbInsert(_ text: String) { parent.text += text }
        func kbDelete() { if !parent.text.isEmpty { parent.text.removeLast() } }
        func kbMoveCursor(_ offset: Int) {}
        func kbTextBefore() -> String? { parent.text }
        func kbNextKeyboard() {}
        func kbDismiss() {}
        func kbSettingsChanged(_ settings: KBSettings) { parent.onSettings(settings) }
        var kbNeedsGlobe: Bool { false }
        var kbFullAccess: Bool { true }
    }
}
