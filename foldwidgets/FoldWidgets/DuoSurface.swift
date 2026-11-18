import SwiftUI

// MARK: - Charnière et zone réservée (iOS 27.1)
//
// Ces deux API sont documentées pour l'iPhone Duo. Elles ne compilent qu'avec
// le drapeau DUO_SDK (Xcode 27.1). Sans ce drapeau, l'app reste un iPhone
// classique : un curseur remplace la charnière.
//
// WidgetKit n'a pas d'équivalent. Le widget choisit sa composition d'après
// sa famille (petit, moyen, grand), jamais d'après l'angle de la charnière.

struct HingeReader: ViewModifier {
    let action: (Bool?, Double?) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        #if DUO_SDK
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, context in
                guard let hinge = context.hinge else {
                    action(nil, nil)
                    return
                }
                let closed: Bool?
                if hinge.status == .closed {
                    closed = true
                } else if hinge.status == .fullyOpen || hinge.status == .partiallyOpen {
                    closed = false
                } else {
                    closed = nil
                }
                action(closed, hinge.angle.degrees)
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension View {
    func onHinge(_ action: @escaping (Bool?, Double?) -> Void) -> some View {
        modifier(HingeReader(action: action))
    }
}

extension GeometryProxy {
    /// Space to keep between the two columns so they don't sit on the fold.
    func foldGutter() -> CGFloat {
        #if DUO_SDK
        if #available(iOS 27.1, *) {
            if let frame = reservedRegions(kind: .division, options: .includeInactive).first?.frame {
                let band = min(frame.width, frame.height)
                if band > 1, band < 160 {
                    return max(16, band)
                }
            }
        }
        #endif
        return size.width > size.height ? 24 : 0
    }
}
