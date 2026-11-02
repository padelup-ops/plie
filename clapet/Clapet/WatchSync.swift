import Foundation
import WatchConnectivity

// MARK: - Envoi des chiffres à l'Apple Watch
//
// À chaque changement, l'app envoie un petit résumé (FoldlyWatchData) par WatchConnectivity.
// Le dernier envoi remplace le précédent : la montre a toujours les chiffres les plus récents.

final class WatchSync: NSObject, WCSessionDelegate {
    static let shared = WatchSync()

    private var pending: FoldlyWatchData?
    private var lastSent: FoldlyWatchData?

    /// Au lancement de l'app : active la session et envoie les chiffres actuels.
    func start(_ stats: ClapetStats) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate == nil { session.delegate = self }
        if session.activationState != .activated { session.activate() }
        push(stats)
    }

    func push(_ stats: ClapetStats) {
        guard WCSession.isSupported(), !Demo.seeded else { return }
        let data = stats.watchData()
        let session = WCSession.default
        if session.delegate == nil { session.delegate = self }
        guard session.activationState == .activated else {
            pending = data
            session.activate()
            return
        }
        send(data, on: session)
    }

    private func send(_ data: FoldlyWatchData, on session: WCSession) {
        guard session.isPaired, session.isWatchAppInstalled else { return }
        // Pas d'envoi si rien n'a changé (sauf l'heure de mise à jour).
        var a = data, b = lastSent
        a.updated = .distantPast
        b?.updated = .distantPast
        if a == b { return }
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        do {
            try session.updateApplicationContext(["data": encoded])
            lastSent = data
        } catch {
            pending = data
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated, let data = pending else { return }
        pending = nil
        DispatchQueue.main.async { self.send(data, on: session) }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Changement de montre : on réactive pour la nouvelle.
        session.activate()
    }
}

extension ClapetStats {
    func watchData(now: Date = Date()) -> FoldlyWatchData {
        FoldlyWatchData(
            day: FoldlyWatchData.key(now),
            today: day(now).closes,
            yesterday: yesterday(now),
            reference: reference(now: now),
            limitOn: goalOn,
            week: lastWeek(now: now).map { $0.closes },
            closedSeconds: downTime(now, now: now),
            openSeconds: openTime(now, now: now),
            openSince: openSince,
            lastClose: lastClose,
            total: totalCloses,
            peakHour: peakHour,
            updated: now)
    }
}
