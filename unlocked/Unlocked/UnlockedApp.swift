import SwiftUI

// MARK: - UNLOCKED : des téléphones trouvés. Le premier : celui de Nina.

@main
struct UnlockedApp: App {
    @State private var state = GameState(story: NinaStory.story, key: "nina.save")

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
        }
    }
}

struct RootView: View {
    @Environment(GameState.self) private var state

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

            if state.showChapterEnd {
                ChapterEndCard()
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: state.unlocked)
        .animation(.spring(duration: 0.4), value: state.banner?.id)
        .animation(.easeInOut, value: state.showChapterEnd)
        .fullScreenCover(item: Binding(get: { state.openApp }, set: { state.openApp = $0 })) { app in
            AppContainer(app: app)
                .environment(state)
                .overlay(alignment: .top) {
                    if let m = state.banner {
                        BannerView(message: m)
                            .environment(state)
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .overlay {
                    if state.showChapterEnd { ChapterEndCard().environment(state) }
                }
        }
    }
}
