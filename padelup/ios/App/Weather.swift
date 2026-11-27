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
