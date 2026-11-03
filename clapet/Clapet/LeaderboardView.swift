import GameKit
import SwiftUI

/// L'écran des classements (Game Center), ouvert depuis le trophée de l'écran d'accueil.
struct LeaderboardView: View {
    @Environment(ClapetModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var gameCenter = GameCenter.shared
    @State private var board: String?
    @State private var ranks: [String: Int] = [:]
    @AppStorage("boardsSeen") private var seen = false

    private var stats: ClapetStats { model.stats }
    private var streak: Int { stats.leaderboardStreak() }
    private var month: Int { stats.daysUnderLimit(since: Calendar.current.date(byAdding: .day, value: -29, to: Date())!) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    scoreCard(icon: "flame.fill", color: .orange,
                              title: Text("Longest streak under your limit"),
                              value: streak, id: GameCenter.streakID)
                    scoreCard(icon: "calendar", color: .blue,
                              title: Text("Days under your limit, last 30 days"),
                              value: month, id: GameCenter.monthID)
                    action
                    Text("Only days when you used your Duo count. Only your two scores are shared, through Apple's Game Center. You can leave anytime.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
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
                if gameCenter.on {
                    ToolbarItem(placement: .secondaryAction) {
                        Button(role: .destructive) { gameCenter.setOn(false) } label: { Text("Leave the leaderboard") }
                    }
                }
            }
            .sheet(item: Binding(get: { board.map(BoardID.init) }, set: { board = $0?.id })) { item in
                LeaderboardScreen(leaderboardID: item.id).ignoresSafeArea()
            }
            .task(id: gameCenter.signedIn) { await loadRanks() }
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
                .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
                .frame(width: 92, height: 92)
                .background(Color.yellow.opacity(0.15), in: Circle())
            Text("How do you compare?")
                .font(.system(.title2, design: .rounded).weight(.bold))
            Text("Stay under your daily limit, day after day, and climb the leaderboards with other Foldly users and your friends.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 6)
    }

    private func scoreCard(icon: String, color: Color, title: Text, value: Int, id: String) -> some View {
        Button {
            if gameCenter.on && gameCenter.signedIn { board = id }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 48, height: 48)
                    .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    title
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(value)")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                        (value == 1 ? Text("day") : Text("days"))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                if let rank = ranks[id] {
                    VStack(spacing: 0) {
                        Text(verbatim: "#\(rank)")
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                            .foregroundStyle(color)
                        Text("Rank")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if gameCenter.on && gameCenter.signedIn {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var action: some View {
        if !stats.goalOn {
            VStack(spacing: 10) {
                Text("Set a daily limit first: your score is the number of days you stay under it.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                Button {
                    model.setGoalOn(true)
                } label: {
                    Label("Turn on my daily limit", systemImage: "target")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .buttonBorderShape(.capsule)
            }
        } else if !gameCenter.on || !gameCenter.signedIn {
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
        } else {
            Button {
                board = GameCenter.streakID
            } label: {
                Label("See the full leaderboards", systemImage: "list.number")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
        }
    }

    private func loadRanks() async {
        guard gameCenter.on, GKLocalPlayer.local.isAuthenticated else { return }
        guard let boards = try? await GKLeaderboard.loadLeaderboards(IDs: [GameCenter.streakID, GameCenter.monthID]) else { return }
        for b in boards {
            if let entry = try? await b.loadEntries(for: [GKLocalPlayer.local], timeScope: .allTime).0, entry.rank > 0 {
                ranks[b.baseLeaderboardID] = entry.rank
            }
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
                .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .topTrailing) {
                    if !seen {
                        Circle().fill(.red).frame(width: 9, height: 9).offset(x: 5, y: -4)
                    }
                }
        }
        .accessibilityLabel(Text("Leaderboards"))
    }
}
