import SwiftUI

/// Une petite vidéo animée qui montre, écran par écran, comment créer l'automatisation dans Raccourcis.
/// Dessinée dans l'app (nette, traduite, claire ou sombre). Se joue en boucle ; toucher la relance.
struct ShortcutTutorialView: View {
    @State private var start = Date()

    static let stepDuration: Double = 3.4
    static let count = 7

    private let captions: [Text] = [
        Text("Open **Shortcuts** and tap **Automation**."),
        Text("Tap **+** to create an automation."),
        Text("Choose **iPhone Opened or Closed**."),
        Text("Keep **Closed** only, choose **Run Immediately**, then **Next**."),
        Text("Search **FoldCount**, pick **Count a fold**, then turn off **Show When Run**."),
        Text("Check that the automation is **on**. Done!"),
        Text("Do the same with **Opened** and **Count an opening** to measure the time open."),
    ]

    /// Où le doigt touche, à chaque étape (en proportion de l'écran).
    private let taps: [CGPoint?] = [
        CGPoint(x: 0.5, y: 0.93),
        CGPoint(x: 0.88, y: 0.075),
        CGPoint(x: 0.5, y: 0.53),
        CGPoint(x: 0.66, y: 0.085),
        CGPoint(x: 0.5, y: 0.28),
        CGPoint(x: 0.86, y: 0.205),
        nil,
    ]

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = max(0, context.date.timeIntervalSince(start))
            let index = Int(elapsed / Self.stepDuration) % Self.count
            let t = elapsed.truncatingRemainder(dividingBy: Self.stepDuration)
            VStack(spacing: 14) {
                // Les segments de progression, comme des stories
                HStack(spacing: 4) {
                    ForEach(0..<Self.count, id: \.self) { i in
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.dfFill)
                                Capsule().fill(Color.dfAccent)
                                    .frame(width: g.size.width * (i < index ? 1 : (i == index ? min(1, t / Self.stepDuration) : 0)))
                            }
                        }
                        .frame(height: 4)
                    }
                }
                GeometryReader { g in
                    let size = g.size
                    ZStack {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color(uiColor: .systemBackground))
                        screen(index, tapped: t > 1.45)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .frame(width: size.width, height: size.height, alignment: .top)
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        finger(index: index, t: t, size: size)
                    }
                }
                .frame(height: 400)
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 6))
                .contentShape(Rectangle())
                .onTapGesture { start = Date() }
                .accessibilityHidden(true)

                captions[index]
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .id(index)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: index)
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Tap the video to start again")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Animated guide: create the automation in Shortcuts."))
    }

    // MARK: Le doigt

    @ViewBuilder
    private func finger(index: Int, t: Double, size: CGSize) -> some View {
        if let target = taps[index] {
            let from = taps[(index + Self.count - 1) % Self.count] ?? CGPoint(x: 0.5, y: 0.75)
            let k = min(1, max(0, (t - 0.25) / 0.9))
            let e = k * k * (3 - 2 * k)
            let p = CGPoint(x: (from.x + (target.x - from.x) * e) * size.width, y: (from.y + (target.y - from.y) * e) * size.height)
            let press = t > 1.25 && t < 1.65
            let ripple = min(1, max(0, (t - 1.3) / 0.5))
            ZStack {
                Circle()
                    .stroke(Color.dfAccent, lineWidth: 3)
                    .frame(width: 30 + 40 * ripple, height: 30 + 40 * ripple)
                    .opacity(t > 1.3 ? 1 - ripple : 0)
                Circle()
                    .fill(Color.gray.opacity(0.45))
                    .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 2))
                    .frame(width: press ? 30 : 36, height: press ? 30 : 36)
            }
            .position(p)
            .opacity(t > Self.stepDuration - 0.3 ? 0 : 1)
        }
    }

    // MARK: Les écrans (une version simplifiée de Raccourcis)

    @ViewBuilder
    private func screen(_ index: Int, tapped: Bool) -> some View {
        switch index {
        case 0: shortcutsHome(tapped: tapped)
        case 1: automationEmpty(tapped: tapped)
        case 2: triggers(tapped: tapped)
        case 3: triggerOptions(tapped: tapped)
        case 4: actions(tapped: tapped)
        case 5: automationList(second: false, tapped: tapped)
        default: automationList(second: true, tapped: true)
        }
    }

    private func title(_ text: Text) -> some View {
        text.font(.title2.weight(.bold)).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ symbol: String, _ color: Color, _ text: Text, highlighted: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(color))
            text.font(.subheadline)
            Spacer()
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(highlighted ? Color.dfAccent.opacity(0.22) : Color.dfCard))
    }

    private func shortcutsHome(tapped: Bool) -> some View {
        VStack(spacing: 10) {
            title(Text("Shortcuts"))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 12)
                        .fill([Color.blue, .orange, .purple, .teal][i].opacity(0.75))
                        .frame(height: 64)
                }
            }
            Spacer()
            HStack {
                tab("square.stack.3d.up.fill", Text("Shortcuts"), on: !tapped)
                tab("checkmark.circle.fill", Text("Automation"), on: tapped)
                tab("square.grid.2x2.fill", Text("Gallery"), on: false)
            }
            .padding(.top, 6)
            .overlay(alignment: .top) { Divider() }
        }
    }

    private func tab(_ symbol: String, _ text: Text, on: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol).font(.body)
            text.font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(on ? Color.blue : Color.secondary)
        .frame(maxWidth: .infinity)
    }

    private func automationEmpty(tapped: Bool) -> some View {
        VStack(spacing: 14) {
            HStack {
                Spacer()
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.blue)
                    .padding(8)
                    .background(Circle().fill(tapped ? Color.dfAccent.opacity(0.3) : Color.clear))
            }
            title(Text("Automation"))
            Spacer()
            Image(systemName: "checkmark.circle").font(.largeTitle).foregroundStyle(.secondary)
            Text("New Automation").font(.subheadline.weight(.semibold)).foregroundStyle(Color.blue)
            Spacer()
        }
    }

    private func triggers(tapped: Bool) -> some View {
        VStack(spacing: 8) {
            title(Text("New Automation"))
            HStack {
                Image(systemName: "magnifyingglass")
                Text("Search").foregroundStyle(.secondary)
                Spacer()
            }
            .font(.subheadline)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.dfFill))
            row("clock.fill", .orange, Text("Time of Day"))
            row("alarm.fill", .orange, Text("Alarm"))
            row("iphone", .blue, Text("iPhone Opened or Closed"), highlighted: tapped)
            row("wifi", .blue, Text("Wi-Fi"))
            row("battery.75percent", .green, Text("Battery Level"))
            Spacer()
        }
    }

    private func triggerOptions(tapped: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "iphone").foregroundStyle(Color.blue)
                Text("When iPhone is").font(.subheadline.weight(.semibold))
                (tapped ? Text("Closed") : Text("Opened or Closed"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(tapped ? Color.dfAccent.opacity(0.25) : Color.blue.opacity(0.1)))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.dfCard))
            VStack(spacing: 0) {
                option(Text("Run After Confirmation"), checked: false)
                Divider()
                option(Text("Run Immediately"), checked: true)
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.dfCard))
            HStack {
                Text("Notify When Run").font(.subheadline)
                Spacer()
                Toggle(isOn: .constant(false)) { EmptyView() }.labelsHidden().scaleEffect(0.8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.dfCard))
            Spacer()
            Text("Next")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(tapped ? Color.blue : Color.blue.opacity(0.4)))
        }
    }

    private func option(_ text: Text, checked: Bool) -> some View {
        HStack {
            text.font(.subheadline)
            Spacer()
            if checked { Image(systemName: "checkmark").foregroundStyle(Color.blue) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }

    private func actions(tapped: Bool) -> some View {
        VStack(spacing: 8) {
            title(Text("Add Action"))
            HStack {
                Image(systemName: "magnifyingglass")
                Text(verbatim: "FoldCount")
                Spacer()
            }
            .font(.subheadline)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.dfFill))
            appRow(Text("Count a fold"), highlighted: tapped)
            appRow(Text("Count an opening"), highlighted: false)
            appRow(Text("Folds today"), highlighted: false)
            Spacer()
        }
    }

    private func appRow(_ text: Text, highlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Image("TutorialIcon")
                .resizable()
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            text.font(.subheadline)
            Spacer()
            Image(systemName: "plus.circle").foregroundStyle(Color.blue)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(highlighted ? Color.dfAccent.opacity(0.22) : Color.dfCard))
    }

    private func automationList(second: Bool, tapped: Bool) -> some View {
        VStack(spacing: 10) {
            title(Text("Automation"))
            automationCard(Text("When iPhone is closed"), Text("Count a fold"), on: tapped)
            if second {
                automationCard(Text("When iPhone is opened"), Text("Count an opening"), on: true)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Spacer()
        }
    }

    private func automationCard(_ trigger: Text, _ action: Text, on: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "iphone").foregroundStyle(Color.blue)
                    trigger.font(.subheadline.weight(.semibold))
                }
                HStack(spacing: 6) {
                    Image("TutorialIcon")
                        .resizable()
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    action.font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Capsule()
                .fill(on ? Color.green : Color.dfFill)
                .frame(width: 42, height: 26)
                .overlay(alignment: on ? .trailing : .leading) {
                    Circle().fill(.white).frame(width: 22, height: 22).padding(2)
                }
                .animation(.spring(response: 0.3), value: on)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.dfCard))
    }
}
