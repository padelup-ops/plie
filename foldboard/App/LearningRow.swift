import SwiftUI
import UIKit

/// « Ton clavier apprend » : ce que le clavier a retenu de ta prise en main, Duo fermé et Duo ouvert.
struct LearningRow: View {
    @State private var learn = KBVault.loadLearn()

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "brain.head.profile")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your keyboard is learning").font(.headline)
                        Text(String(format: NSLocalizedString("%lld habits learned", comment: ""), learn.all))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: Double(min(learn.all, Self.goal)), total: Double(Self.goal))
                    .tint(learn.all >= Self.goal ? .green : .accentColor)
                HStack {
                    level("Duo closed", learn.closed)
                    Spacer()
                    level("Duo open", learn.open)
                }
                if let a = learn.accuracy {
                    // Combien de fois le clavier a choisi le bon côté tout seul (sans être corrigé juste après).
                    Label {
                        Text(String(format: NSLocalizedString("Right side on its own: %lld%% of the time", comment: ""), Int((a * 100).rounded())))
                    } icon: {
                        Image(systemName: "scope")
                    }
                    .font(.subheadline)
                    .foregroundStyle(a >= 0.8 ? Color.green : .secondary)
                }
            }
            .padding(.vertical, 4)
        } footer: {
            Text("Each time you type, or move the keyboard to the other side, Foldboard learns how you hold your Duo. The more you use it, the less you need to.")
        }
        .onAppear { learn = KBVault.loadLearn() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            learn = KBVault.loadLearn()
        }
    }

    static let goal = 25

    private func level(_ name: LocalizedStringKey, _ n: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            Text(n == 0 ? LocalizedStringKey("Not yet") : (n < 10 ? LocalizedStringKey("Learning") : LocalizedStringKey("Knows you well")))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(n >= 10 ? .green : .primary)
        }
    }
}
