import SwiftUI

// MARK: - Mises en page qui évitent la charnière
//
// Duo plié en L : la moitié du haut est debout (on la lit), celle du bas est à plat (on la touche).
// Un menu centré sur tout l'écran tombe en plein sur la pliure. Ces deux conteneurs coupent l'écran
// exactement à la charnière : ce qu'on lit en haut, ce qu'on choisit en bas.

/// `top` sur la moitié debout, `bottom` sur la moitié à plat. Chaque moitié défile si besoin.
struct HingeSplit<Top: View, Bottom: View>: View {
    let top: Top
    let bottom: Bottom

    init(@ViewBuilder top: () -> Top, @ViewBuilder bottom: () -> Bottom) {
        self.top = top()
        self.bottom = bottom()
    }

    var body: some View {
        GeometryReader { proxy in
            let half = proxy.size.height / 2
            let safeTop = proxy.safeAreaInsets.top
            let safeBottom = proxy.safeAreaInsets.bottom
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    top
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: max(0, half - safeTop - 16))
                        .padding(.top, safeTop)
                        .padding(.bottom, 16)
                }
                .frame(height: half)
                ScrollView(showsIndicators: false) {
                    bottom
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: max(0, half - safeBottom - 16))
                        .padding(.top, 16)
                        .padding(.bottom, safeBottom)
                }
                .frame(height: half)
            }
        }
        .ignoresSafeArea()
    }
}

/// Pose une carte (résultat, choix) au milieu de la moitié basse, celle qui est à plat sous les doigts.
struct LowerHalf<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: proxy.size.height / 2)
                    .allowsHitTesting(false)
                ScrollView(showsIndicators: false) {
                    content
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: max(0, proxy.size.height / 2 - proxy.safeAreaInsets.bottom - 12))
                }
                .padding(.top, 12)
                .padding(.bottom, proxy.safeAreaInsets.bottom)
                .frame(height: proxy.size.height / 2)
            }
        }
        .ignoresSafeArea()
    }
}
