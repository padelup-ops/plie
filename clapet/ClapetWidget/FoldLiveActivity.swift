import ActivityKit
import SwiftUI
import WidgetKit

// Le compteur en direct : écran verrouillé (et écran extérieur du téléphone plié), Dynamic Island.

private let liveMint = Color(red: 0.36, green: 0.89, blue: 0.78)
private let liveOrange = Color(red: 1.0, green: 0.71, blue: 0.36)
private let liveRed = Color(red: 1.0, green: 0.45, blue: 0.42)

private func tone(_ s: FoldActivityAttributes.ContentState) -> Color {
    if s.limit > 0 && s.today > s.limit { return liveRed }
    if s.limit > 0 && Double(s.today) >= 0.8 * Double(s.limit) { return liveOrange }
    return liveMint
}

private func statusText(_ s: FoldActivityAttributes.ContentState) -> Text {
    if s.left > 0 { return Text("\(s.left) left") }
    if s.left == 0 { return Text("Limit reached") }
    return Text("\(-s.left) over")
}

struct FoldLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FoldActivityAttributes.self) { context in
            FoldLockScreenView(state: context.state.fresh(context.isStale))
                .activityBackgroundTint(Color(red: 0.055, green: 0.078, blue: 0.078))
                .activitySystemActionForegroundColor(liveMint)
        } dynamicIsland: { context in
            let s = context.state.fresh(context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(s.today)")
                            .font(.system(size: 34, weight: .light))
                            .monospacedDigit()
                        Text("folds today")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    statusText(s)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tone(s))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: s.progress)
                        .tint(tone(s))
                }
            } compactLeading: {
                Image(systemName: "rectangle.compress.vertical")
                    .foregroundStyle(tone(s))
            } compactTrailing: {
                Text("\(s.today)")
                    .monospacedDigit()
                    .foregroundStyle(tone(s))
            } minimal: {
                Text("\(s.today)")
                    .monospacedDigit()
                    .foregroundStyle(tone(s))
            }
        }
    }
}

struct FoldLockScreenView: View {
    let state: FoldActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.compress.vertical")
                    Text(verbatim: "Foldly")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(liveMint)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(state.today)")
                        .font(.system(size: 44, weight: .light))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("folds today")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                statusText(state)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tone(state))
                ProgressView(value: state.progress)
                    .tint(tone(state))
                    .frame(width: 110)
                Text("Limit \(state.limit)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(16)
    }
}
