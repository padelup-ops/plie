import SwiftUI

// MARK: - Fonctions propres à l'iPhone Duo
//
// Tout le code qui appelle les API de l'iPhone Duo (iOS 27.1) est entouré de `#if DUO_SDK`.
// Ce drapeau est activé dans les réglages du projet
// (Build Settings > Swift Compiler - Custom Flags > Active Compilation Conditions).
// Il faut Xcode 27.1 ou plus récent pour compiler avec. Avec un Xcode plus ancien,
// retire DUO_SDK de ce réglage : l'app compile alors avec les commandes au doigt seulement.

enum DuoSupport {
    /// Vrai si l'app a été compilée avec le SDK Duo et tourne sur iOS 27.1 ou plus.
    static var apisAvailable: Bool {
        #if DUO_SDK
        if #available(iOS 27.1, *) { return true }
        #endif
        return false
    }
}

// MARK: - Charnière

/// Transmet l'angle de la charnière en degrés (180 = à plat), ou nil si l'appareil n'en a pas.
struct HingeAngleReader: ViewModifier {
    let action: (Double?) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        #if DUO_SDK
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, newContext in
                action(newContext.hinge?.angle.degrees)
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
    /// Appelé à chaque mouvement de la charnière de l'iPhone Duo.
    func onHingeAngle(_ action: @escaping (Double?) -> Void) -> some View {
        modifier(HingeAngleReader(action: action))
    }
}

/// Convertit l'angle de la charnière en une valeur de 0 à 1.
/// 80° (ouvert en L, l'écran reste lisible) donne 0, 180° (à plat) donne 1.
enum HingeMapping {
    static let lowDegrees = 80.0
    static let highDegrees = 180.0

    static func fraction(fromDegrees degrees: Double) -> Double {
        let value = (degrees - lowDegrees) / (highDegrees - lowDegrees)
        return min(1, max(0, value))
    }
}

// MARK: - Écran extérieur pendant la capture caméra

/// Affiche `outer` sur l'écran extérieur du Duo ouvert, pendant que la caméra tourne.
/// C'est le seul moyen prévu par iOS 27.1 pour utiliser l'écran extérieur quand le Duo est ouvert :
/// il est pensé pour montrer quelque chose à la personne filmée, ce qui est exactement le cas ici.
struct OuterScreenAccessory<Outer: View>: ViewModifier {
    @Binding var isEnabled: Bool
    let onAvailabilityChange: (Bool) -> Void
    let outer: () -> Outer

    @ViewBuilder
    func body(content: Content) -> some View {
        #if DUO_SDK
        if #available(iOS 27.1, *) {
            content
                .sceneAccessory {
                    CameraCaptureAccessory(isEnabled: $isEnabled) {
                        outer()
                    }
                    .onAvailabilityChange { available in
                        onAvailabilityChange(available)
                    }
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
    func outerScreen<Outer: View>(isEnabled: Binding<Bool>,
                                  onAvailabilityChange: @escaping (Bool) -> Void,
                                  @ViewBuilder content: @escaping () -> Outer) -> some View {
        modifier(OuterScreenAccessory(isEnabled: isEnabled,
                                      onAvailabilityChange: onAvailabilityChange,
                                      outer: content))
    }
}
