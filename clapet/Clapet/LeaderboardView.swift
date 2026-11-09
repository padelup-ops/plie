import GameKit
import SwiftUI

/// L'écran des classements (Game Center), ouvert depuis le trophée de l'écran d'accueil. Ouvert à tous.
struct LeaderboardView: View {
    @Environment(ClapetModel.self) private var model
    @Environment(ClapetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var gameCenter = GameCenter.shared
    @State private var board: String?
    @State private var ranks: [String: Int] = [:]
    @State private var showRules = false
    @AppStorage("boardsSeen") private var seen = false

    private var stats: ClapetStats { model.stats }
    private var joined: Bool { gameCenter.on && gameCenter.signedIn }

    var body: some View {
        let scores = gameCenter.scores(stats)
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    join

                    section(Text("Who folds the most?"), symbol: "flame.fill", color: .orange)
                    scoreCard(icon: "sun.max.fill", color: .orange, title: Text("Today"),
                              value: Text("\(FoldUnit.shown(scores[GameCenter.todayID] ?? 0)) folds"), id: GameCenter.todayID)
                    scoreCard(icon: "calendar.day.timeline.left", color: .pink, title: Text("This week"),
                              value: Text("\(FoldUnit.shown(scores[GameCenter.weekID] ?? 0)) folds"), id: GameCenter.weekID)
                    scoreCard(icon: "infinity", color: .purple, title: Text("Since day one"),
                              value: Text("\(FoldUnit.shown(scores[GameCenter.totalID] ?? 0)) folds"), id: GameCenter.totalID)

                    contestHeader
                    scoreCard(icon: "trophy.fill", color: .yellow, title: Text("Most folds"),
                              value: Text("\(FoldUnit.shown(scores[GameCenter.contestFoldsID] ?? 0)) folds"), id: GameCenter.contestFoldsID)
                    scoreCard(icon: "iphone.gen3", color: .blue, title: Text("Most time unfolded"),
                              value: Text(TimeFormat.short(TimeInterval((scores[GameCenter.contestOpenID] ?? 0) * 60))), id: GameCenter.contestOpenID)
                    scoreCard(icon: "leaf.fill", color: .green, title: Text("The calmest (fewest folds per day)"),
                              value: scores[GameCenter.contestCalmID].map { Text("\(Double($0) / 10, format: .number.precision(.fractionLength(1))) per day") }
                                ?? Text("From \(GameCenter.calmMinDays) days of use"),
                              id: GameCenter.contestCalmID)

                    section(Text("Under your limit"), symbol: "target", color: .teal)
                    if stats.goalOn {
                        scoreCard(icon: "flame", color: .teal, title: Text("Longest streak under your limit"),
                                  value: Text("\(scores[GameCenter.streakID] ?? 0) days"), id: GameCenter.streakID)
                        scoreCard(icon: "calendar", color: .teal, title: Text("Days under your limit, last 30 days"),
                                  value: Text("\(scores[GameCenter.monthID] ?? 0) days"), id: GameCenter.monthID)
                    } else {
                        Button {
                            model.setGoalOn(true)
                        } label: {
                            Label("Turn on my daily limit", systemImage: "target")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .buttonBorderShape(.capsule)
                    }

                    Text("Only your scores and your Game Center nickname are shared, through Apple's Game Center. You can leave anytime.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                        .padding(.top, 6)
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(Text("Leaderboards"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: shareText) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel(Text("Share my rank"))
                }
                if gameCenter.on {
                    ToolbarItem(placement: .secondaryAction) {
                        Button(role: .destructive) { gameCenter.setOn(false) } label: { Text("Leave the leaderboard") }
                    }
                }
            }
            .sheet(item: Binding(get: { board.map(BoardID.init) }, set: { board = $0?.id })) { item in
                LeaderboardScreen(leaderboardID: item.id).ignoresSafeArea()
            }
            .sheet(isPresented: $showRules) { ContestRulesView() }
            .task(id: gameCenter.signedIn) {
                await gameCenter.loadPeriods()
                await loadRanks()
            }
            .onAppear {
                seen = true
                gameCenter.submit(stats)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 46))
                .foregroundStyle(Color.orange)
                .frame(width: 92, height: 92)
                .background(Color.yellow.opacity(0.15), in: Circle())
            Text("How do you compare?")
                .font(.system(.title2, design: .rounded).weight(.bold))
            Text("Climb the leaderboards with other Foldly users and your friends. Free for everyone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 6)
    }

    private func section(_ title: Text, symbol: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color)
            title
            Spacer()
        }
        .font(.system(.headline, design: .rounded))
        .padding(.top, 10)
    }

    /// Le concours du mois : le lot, la date de fin et le règlement.
    private var contestHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            section(Text("Contest of the month"), symbol: "gift.fill", color: .yellow)
            VStack(alignment: .leading, spacing: 8) {
                Text("Each month, the winner of each category gets Foldly+ for free and picks a new feature for the app.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if let end = gameCenter.periods[GameCenter.contestFoldsID]?.end {
                        Label { Text("Ends \(end.formatted(.dateTime.day().month(.wide)))") } icon: { Image(systemName: "hourglass") }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { showRules = true } label: { Text("Rules") }
                        .font(.footnote.weight(.semibold))
                }
            }
            .padding(16)
            .background(LinearGradient(colors: [Color.yellow.opacity(0.22), Color.orange.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func scoreCard(icon: String, color: Color, title: Text, value: Text, id: String) -> some View {
        Button {
            if joined { board = id }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 44, height: 44)
                    .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    title
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    value
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
                Spacer(minLength: 4)
                if let rank = ranks[id] {
                    VStack(spacing: 0) {
                        Text(verbatim: rank <= 3 ? ["🥇", "🥈", "🥉"][rank - 1] : "#\(rank)")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundStyle(color)
                        Text("Rank")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if joined {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var join: some View {
        if !joined {
            VStack(spacing: 8) {
                Button {
                    gameCenter.setOn(true)
                    gameCenter.submit(stats)
                } label: {
                    Label("Join with Game Center", systemImage: "gamecontroller.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .buttonBorderShape(.capsule)
                if let problem = gameCenter.problem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    /// Le texte à partager : mon meilleur rang, sinon mes plis du jour.
    private var shareText: String {
        let link = "https://apps.apple.com/app/id\(UpdateCheck.appID)"
        let today = FoldUnit.shown(stats.day().closes)
        if let r = ranks[GameCenter.todayID] {
            return String(localized: "I'm #\(r) on today's Foldly leaderboard with \(today) folds! Can you beat me? \(link)")
        }
        return String(localized: "\(today) folds today on my iPhone Duo. Can you beat me on the Foldly leaderboard? \(link)")
    }

    private func loadRanks() async {
        guard gameCenter.on, GKLocalPlayer.local.isAuthenticated else { return }
        guard let boards = try? await GKLeaderboard.loadLeaderboards(IDs: GameCenter.all) else { return }
        for b in boards {
            if let entry = try? await b.loadEntries(for: [GKLocalPlayer.local], timeScope: .allTime).0, entry.rank > 0 {
                ranks[b.baseLeaderboardID] = entry.rank
            }
        }
    }
}

/// Le règlement du concours (obligatoire pour un concours dans une app).
struct ContestRulesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    rule("1", Text("Free and open to everyone who uses Foldly and joins the leaderboard with Game Center. No purchase needed."))
                    rule("2", Text("Each contest lasts about a month. The end date is shown in the app. A new contest starts right after."))
                    rule("3", Text("Three categories: most folds, most time unfolded, and the calmest (fewest folds per day, with at least 7 days of use in the period). Only folds counted automatically by the app are meant to count."))
                    rule("4", Text("The winner of each category is the first in Game Center when the contest ends. Scores that look impossible or made by cheating can be excluded."))
                    rule("5", Text("Prize for each winner: Foldly+ for free (a code to redeem on the App Store) and the chance to suggest a new feature, which we will build first if it is possible and allowed on the App Store."))
                    rule("6", Text("Winners are announced on Reddit (r/iPhoneduoapp). To get the prize, contact us within 30 days through the Support link on Foldly's App Store page, with a screenshot of your Game Center nickname."))
                    rule("7", Text("Apple is not a sponsor of this contest and is not involved in it in any way."))
                }
                .padding(20)
            }
            .navigationTitle(Text("Contest rules"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func rule(_ n: String, _ text: Text) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: n)
                .font(.system(.headline, design: .rounded))
                .frame(width: 28, height: 28)
                .background(Color.dfAccent.opacity(0.18), in: Circle())
            text.font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct BoardID: Identifiable { let id: String }

/// Le trophée de l'écran d'accueil (avec un point tant que l'écran n'a jamais été ouvert).
struct LeaderboardButton: View {
    @Binding var show: Bool
    @AppStorage("boardsSeen") private var seen = false

    var body: some View {
        Button { show = true } label: {
            Image(systemName: "trophy.fill")
                .foregroundStyle(Color.orange)
                .overlay(alignment: .topTrailing) {
                    if !seen {
                        Circle().fill(.red).frame(width: 9, height: 9).offset(x: 5, y: -4)
                    }
                }
        }
        .accessibilityLabel(Text("Leaderboards"))
    }
}
