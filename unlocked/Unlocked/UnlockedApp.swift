import SwiftUI

// MARK: - UNLOCKED : des téléphones trouvés. Le premier : celui de Nina.

@main
struct UnlockedApp: App {
    @State private var state = GameState(story: NinaStory.story, key: "nina.save")
    @State private var store = Store()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .environment(store)
                .task {
                    await store.start()
                    if let shot = UserDefaults.standard.string(forKey: "shot") {
                        state.prepareShot(shot)
                    } else {
                        state.fullStory = store.purchased
                    }
                }
                .onChange(of: store.purchased) { _, owned in
                    state.fullStory = owned
                    if owned { state.showPaywall = false }
                }
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
        }
    }
}

struct RootView: View {
    @Environment(GameState.self) private var state
    @Environment(Store.self) private var store

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            if state.unlocked {
                HomeScreen()
                    .scaleEffect(state.openApp == nil ? 1 : 0.92)
                    .blur(radius: state.openApp == nil ? 0 : 6)
                    .transition(.asymmetric(insertion: .scale(scale: 1.15).combined(with: .opacity), removal: .opacity))
            } else {
                LockScreen()
                    .transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 1.1).combined(with: .opacity)))
            }

            if let app = state.openApp {
                AppScreen(app: app)
                    .id(app)
                    .transition(.scale(scale: 0.15).combined(with: .opacity))
                    .zIndex(5)
            }

            if let m = state.banner {
                BannerView(message: m)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }

            if let n = state.showChapterEnd {
                ChapterEndCard(number: n)
                    .transition(.opacity)
                    .zIndex(20)
            }

            if state.showPaywall {
                PaywallCard()
                    .transition(.opacity)
                    .zIndex(30)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: state.unlocked)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: state.openApp)
        .animation(.spring(duration: 0.4), value: state.banner?.id)
        .animation(.easeInOut, value: state.showChapterEnd)
        .animation(.easeInOut, value: state.showPaywall)
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .bottom)
    }
}
