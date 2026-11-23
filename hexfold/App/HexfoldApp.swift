// HexfoldApp.swift — Hexfold
//
// Unciv (MPL-2.0, Yair Morgenstern et ses contributeurs) sur iPhone : la version navigateur du jeu, embarquée dans
// l'app et servie par un petit serveur local (127.0.0.1) à une vue web plein écran. Tout marche hors ligne ; les
// parties sont gardées par WebKit (IndexedDB) d'une ouverture à l'autre.

import SwiftUI

@main
struct HexfoldApp: App {
    var body: some Scene {
        WindowGroup {
            GameView()
                .ignoresSafeArea()
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
                .background(Color.black)
        }
    }
}
