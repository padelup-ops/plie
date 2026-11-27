import SwiftUI
import Foundation

// Météo de jeu (Open-Meteo : libre, sans clé). Pour les terrains extérieurs : pluie, vent, température,
// et un indice padel sur 100 pour chaque heure.
enum WeatherAPI {
    static func forecast(latitude: Double, longitude: Double) async throws -> [WeatherHour] {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", longitude)),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,wind_speed_10m,weather_code"),
            URLQueryItem(name: "forecast_days", value: "3"),
            URLQueryItem(name: "timezone", value: "UTC"),
        ]
        let (data, resp) = try await URLSession.shared.data(from: comps.url!)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hourly = root["hourly"] as? [String: Any],
              let times = hourly["time"] as? [String] else { throw URLError(.badServerResponse) }
        // Valeurs pouvant être nulles : on lit chaque case séparément.
        func series(_ key: String) -> [Double?] { (hourly[key] as? [Any] ?? []).map { ($0 as? NSNumber)?.doubleValue } }
        let temps = series("temperature_2m"), rain = series("precipitation_probability")
        let wind = series("wind_speed_10m"), codes = series("weather_code")
        func at(_ a: [Double?], _ i: Int, _ fallback: Double) -> Double { i < a.count ? (a[i] ?? fallback) : fallback }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        var out: [WeatherHour] = []
        for (i, t) in times.enumerated() {
            guard let date = f.date(from: t) else { continue }
            out.append(WeatherHour(time: date, temperature: at(temps, i, 0), rainChance: Int(at(rain, i, 0)),
                                   wind: at(wind, i, 0), code: Int(at(codes, i, 3))))
        }
        return out.filter { $0.time > Date().addingTimeInterval(-3600) }
    }
}


/// Météo de jeu : une barre par heure, haute quand il fait bon jouer dehors, en jaune balle au-dessus de 70/100.
struct PlayWeatherChart: View {
    var hours: [WeatherHour]
    var indoor = false

    private var bestWindow: String? {
        var best: (Int, Int)? = nil
        var start: Int? = nil
        for (i, h) in hours.enumerated() {
            if h.playScore >= 70 { if start == nil { start = i } } else { start = nil }
            if let s = start, (best == nil || i - s > best!.1 - best!.0) { best = (s, i) }
        }
        guard let b = best else { return nil }
        let a = FR.string(hours[b.0].time, "HH'h'"), z = FR.string(hours[b.1].time.addingTimeInterval(3600), "HH'h'")
        return b.0 == b.1 ? "Bon pour jouer dehors vers \(a)." : "Bon pour jouer dehors de \(a) à \(z)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(indoor ? "Terrains couverts : la météo ne compte pas." : (bestWindow ?? "Pas idéal pour jouer dehors dans les prochaines heures."))
                .font(UI.callout()).foregroundStyle(UI.ink)
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(hours) { h in
                    VStack(spacing: 6) {
                        Text("\(Int(h.temperature.rounded()))°").font(UI.score(13)).foregroundStyle(UI.muted)
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(UI.sunken).frame(height: 64)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(h.playScore >= 70 ? UI.ball : (h.playScore >= 40 ? UI.ink.opacity(0.35) : UI.ink.opacity(0.15)))
                                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .strokeBorder(h.playScore >= 70 ? UI.ink.opacity(0.25) : Color.clear, lineWidth: 0.5))
                                .frame(height: max(4, 64 * CGFloat(h.playScore) / 100))
                        }
                        .frame(width: 12)
                        Image(systemName: h.symbol).symbolRenderingMode(.hierarchical).font(.system(size: 11)).foregroundStyle(UI.muted)
                            .frame(height: 12)
                        Text(FR.string(h.time, "HH")).font(UI.score(12)).foregroundStyle(UI.faint)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(FR.string(h.time, "HH'h'")), \(Int(h.temperature.rounded())) degrés, indice \(h.playScore) sur 100")
                }
            }
        }
    }
}
