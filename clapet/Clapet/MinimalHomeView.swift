import SwiftUI

// MARK: - Le look « Épuré »
//
// Noir sur blanc (ou blanc sur noir, selon l'iPhone) : un grand chiffre fin au centre, une ligne,
// un trait jusqu'au repère, trois chiffres, la semaine en sept traits, et des liens en texte.
// Pas de cartes, pas d'icônes, pas de couleurs.

struct MinimalHomeView: View {
    @Environment(ClapetModel.self) private var model
    @Environment(ClapetStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var showWeek = false
    @State private var showAuto = false
    @State private var showAdjust = false
    @State private var showShare = false
    @State private var showWidgets = false
    @State private var plusReason: PlusReason?
    @State private var weekHidden = false
    @State private var surveyHidden = false
    @State private var bump = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                topBar
                    .padding(.top, 8)
                Spacer(minLength: 44)
                hero
                Spacer(minLength: 40)
                figures
                Spacer(minLength: 40)
                week
                Spacer(minLength: 36)
                notices
                links
                    .padding(.top, 28)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .tint(.primary)
        .modifier(HingeReader { closed, degrees in model.hinge(closed: closed, degrees: degrees) })
        .sheet(isPresented: $showSettings) { SettingsView().environment(model).environment(store) }
        .sheet(isPresented: $showAuto) { AutoCountView().environment(model) }
        .sheet(isPresented: $showWeek, onDismiss: { weekHidden = !WeekRecapRule.shouldShowCard(model.stats) }) {
            WeekRecapView().environment(model)
        }
        .sheet(isPresented: $showShare) { ShareDaySheet().environment(model) }
        .sheet(isPresented: $showAdjust) {
            AdjustCountView().environment(model)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showWidgets) { WidgetsHelpView().environment(model).environment(store) }
        .sheet(isPresented: $showHistory) { HistoryView().environment(model) }
        .sheet(item: $plusReason) { reason in
            PlusView(reason: reason.text).environment(model).environment(store)
        }
        .onOpenURL { url in
            if url.host == "plus" && !store.hasPlus { plusReason = .widget }
            if url.host == "week" { showWeek = true }
            if SurveyRule.isAnswerLink(url) {
                SurveyRule.markAnswered()
                withAnimation { surveyHidden = true }
            }
        }
        .task {
            // Une seule fois, après 3 jours suivis : on présente Foldly+ (sans insister).
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            let d = UserDefaults.standard
            if !Demo.seeded && !store.hasPlus && model.stats.daysCounted >= 3 && !d.bool(forKey: "plusPromptShown") {
                d.set(true, forKey: "plusPromptShown")
                plusReason = .tracking
            }
        }
        .onChange(of: model.claps) { _, _ in
            bump = false
            withAnimation(.easeOut(duration: 0.2)) { bump = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeOut(duration: 0.3)) { bump = false }
            }
        }
    }

    // MARK: En haut

    private var topBar: some View {
        HStack {
            Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.footnote)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer()
            Menu {
                Button { showShare = true } label: { Label { Text("Share my day") } icon: { Image(systemName: "square.and.arrow.up") } }
                Button { DeskCenter.shared.showing = true } label: { Label { Text("Desk mode") } icon: { Image(systemName: "laptopcomputer") } }
                Button { showWidgets = true } label: { Label { Text("Widgets") } icon: { Image(systemName: "square.grid.2x2") } }
                Button { showAdjust = true } label: { Label { Text("Adjust the count") } icon: { Image(systemName: "pencil") } }
                Button { showAuto = true } label: { Label { Text("Automatic counting") } icon: { Image(systemName: "bolt.badge.automatic") } }
                if !store.hasPlus {
                    Button { plusReason = .menu } label: { Label { Text("Foldly+") } icon: { Image(systemName: "plus.circle") } }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("More"))
        }
    }

    // MARK: Le chiffre du jour

    private var hero: some View {
        let s = model.stats
        return VStack(spacing: 10) {
            Text("\(s.today)")
                .font(.system(size: 128, weight: .ultraLight))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.25), value: s.today)
                .overlay(alignment: .topTrailing) {
                    Text("+1")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .offset(x: 18, y: bump ? 6 : 20)
                        .opacity(bump ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    // Sans charnière : on touche le chiffre pour compter.
                    guard !model.hasHinge else { return }
                    model.clap()
                }
                .onLongPressGesture { showAdjust = true }
                .accessibilityHint(Text("Touch and hold to adjust the count"))
            Text("folds today")
                .font(.subheadline)
                .tracking(0.6)
                .foregroundStyle(.secondary)
            status
                .font(.subheadline)
                .foregroundStyle(.primary)
                .padding(.top, 14)
            hairline(s.progress)
                .frame(width: 160)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    private var status: Text {
        let s = model.stats
        if s.goalOn {
            let left = s.left()
            if left > 0 { return Text("\(left) left today") }
            if left == 0 { return Text("Limit reached") }
            return Text("\(-left) over the limit")
        }
        return AverageText.status(today: s.today, average: s.averageRef())
    }

    private func hairline(_ value: Double) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(Color.primary)
                    .frame(width: max(2, g.size.width * value))
                    .animation(.easeInOut(duration: 0.4), value: value)
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }

    // MARK: Trois chiffres

    private var figures: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let s = model.stats
            HStack(alignment: .top, spacing: 0) {
                figure(Text("Open"), TimeFormat.short(s.openTime(now, now: now)))
                figure(Text("Closed"), s.autoLast == nil && s.closedTime(now, now: now) == 0 ? "—" : TimeFormat.short(s.closedTime(now, now: now)))
                figure(Text("Yesterday"), "\(s.yesterday(now))")
            }
        }
    }

    private func figure(_ title: Text, _ value: String) -> some View {
        VStack(spacing: 4) {
            title
                .font(.caption2)
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .light))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: La semaine, en sept traits

    private var week: some View {
        let s = model.stats
        let days = s.lastWeek()
        let ref = s.reference()
        let top = Double(max(1, days.map(\.closes).max() ?? 1, ref ?? 0))
        let height: CGFloat = 64
        return VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                if let ref, ref > 0 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.25))
                        .frame(height: 1)
                        .mask(HStack(spacing: 3) { ForEach(0..<60, id: \.self) { _ in Rectangle().frame(width: 3) } })
                        .offset(y: -height * CGFloat(Double(ref) / top))
                }
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(0..<days.count, id: \.self) { i in
                        Capsule()
                            .fill(Color.primary.opacity(i == days.count - 1 ? 1 : 0.3))
                            .frame(width: 3, height: max(3, height * CGFloat(Double(days[i].closes) / top)))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: height, alignment: .bottom)
            HStack(spacing: 0) {
                ForEach(0..<days.count, id: \.self) { i in
                    Text(days[i].date, format: .dateTime.weekday(.narrow))
                        .font(.caption2)
                        .foregroundStyle(i == days.count - 1 ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            Text("\(s.weekTotal) this week")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(s.weekTotal) this week"))
    }

    // MARK: Les messages (en simples lignes)

    @ViewBuilder
    private var notices: some View {
        let s = model.stats
        VStack(spacing: 14) {
            if s.autoLast == nil && !Demo.seeded {
                notice(Text("Count even when the app is closed")) { showAuto = true }
            }
            if !weekHidden && WeekRecapRule.shouldShowCard(s) {
                notice(Text("Your week is ready")) { showWeek = true }
            }
            if !surveyHidden && SurveyRule.shouldShowCard(isTestBuild: store.isTestBuild) {
                notice(Text("Your take in 1 minute")) { openURL(SurveyRule.url) }
            }
        }
    }

    private func notice(_ text: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                text
                Image(systemName: "arrow.right")
                    .font(.footnote)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.vertical, 4)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.primary).frame(height: 1).offset(y: 2)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Les liens

    private var links: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) { linkButtons }
            VStack(spacing: 12) { linkButtons }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var linkButtons: some View {
        Button { showWeek = true } label: { Text("Weekly recap") }
        Button {
            if store.hasPlus { showHistory = true } else { plusReason = .history }
        } label: { Text("History") }
        Button { showSettings = true } label: { Text("Settings") }
    }
}
