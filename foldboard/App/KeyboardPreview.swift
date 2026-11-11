import SwiftUI
import UIKit

/// Le vrai clavier Foldboard, dans l'app : pour voir les réglages et les essayer.
struct KeyboardPreview: UIViewRepresentable {
    var settings: KBSettings
    var pro: Bool
    @Binding var text: String
    var onSettings: (KBSettings) -> Void = { _ in }
    /// Étalonnage : la prise enregistrée, et ce qu'on fait de chaque appui.
    var record: KBGrip? = nil
    var onSample: (([Double]) -> Void)? = nil
    var onSwipe: (([Double]) -> Void)? = nil
    /// Tutoriel : comme sur l'écran extérieur, même Duo ouvert.
    var demoOneHand = false
    /// Captures : la situation imposée.
    var demoContext: String? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> KeyboardCanvas {
        let c = KeyboardCanvas()
        c.input = context.coordinator
        c.demoOneHand = demoOneHand
        c.demoContext = demoContext
        c.configure(settings: settings, pro: pro)
        c.appeared()
        if let record {
            let co = context.coordinator
            c.setRecording(record, { [weak co] f in co?.parent.onSample?(f) },
                           swipes: { [weak co] f in co?.parent.onSwipe?(f) })
        }
        context.coordinator.lastText = text
        DispatchQueue.main.async { c.textChanged() }
        return c
    }

    func updateUIView(_ view: KeyboardCanvas, context: Context) {
        context.coordinator.parent = self
        if view.settings != settings || view.pro != pro {
            view.configure(settings: settings, pro: pro)
        }
        if context.coordinator.lastText != text {
            context.coordinator.lastText = text
            DispatchQueue.main.async { view.textChanged() }
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
        var lastText = ""
        init(_ p: KeyboardPreview) { parent = p }

        func kbInsert(_ text: String) { parent.text += text; lastText = parent.text }
        func kbDelete() { if !parent.text.isEmpty { parent.text.removeLast() }; lastText = parent.text }
        func kbMoveCursor(_ offset: Int) {}
        func kbTextBefore() -> String? { parent.text }
        func kbTextAfter() -> String? { "" }
        func kbNextKeyboard() {}
        func kbDismiss() {}
        func kbSettingsChanged(_ settings: KBSettings) { parent.onSettings(settings) }
        var kbNeedsGlobe: Bool { false }
        var kbFullAccess: Bool { true }
        func kbRecheckPro(_ done: @escaping (Bool) -> Void) { done(parent.pro) }
    }
}
