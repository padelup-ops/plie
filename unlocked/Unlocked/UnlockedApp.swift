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
                    state.fullStory = store.purchased
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
            if state.unlocked {
                HomeScreen()
                    .transition(.opacity)
            } else {
                LockScreen()
                    .transition(.opacity)
            }

            if let m = state.banner {
                BannerView(message: m)
                    .padding(.top, 8)
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
        .animation(.easeInOut(duration: 0.35), value: state.unlocked)
        .animation(.spring(duration: 0.4), value: state.banner?.id)
        .animation(.easeInOut, value: state.showChapterEnd)
        .animation(.easeInOut, value: state.showPaywall)
        .fullScreenCover(item: Binding(get: { state.openApp }, set: { state.openApp = $0 })) { app in
            AppContainer(app: app)
                .environment(state)
                .environment(store)
                .overlay(alignment: .top) {
                    if let m = state.banner {
                        BannerView(message: m)
                            .environment(state)
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .overlay {
                    if let n = state.showChapterEnd { ChapterEndCard(number: n).environment(state) }
                }
        }
    }
}
