import SwiftUI

// MARK: - Chapitre 3 : Plans, Météo+, Réglages

// MARK: Plans

struct MapsApp: View {
    @Environment(GameState.self) private var state
    @State private var selected: String?

    var body: some View {
        let trips = state.story.trips
        let days = trips.reduce(into: [String]()) { if !$0.contains($1.day) { $0.append($1.day) } }
        List {
            Section {
                MapDrawing(places: state.story.places, highlight: trips.first { $0.id == selected }?.stops ?? trips.flatMap(\.stops))
                    .frame(height: 230)
                    .listRowInsets(EdgeInsets())
            }
            ForEach(days, id: \.self) { day in
                Section(day) {
                    ForEach(trips.filter { $0.day == day }) { t in
                        NavigationLink(value: t.id) {
                            HStack(spacing: 12) {
                                Image(systemName: t.mode)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(Color.blue.opacity(0.15)))
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.title).font(.body.weight(.semibold))
                                    Text(t.time).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationDestination(for: String.self) { id in
            if let t = trips.first(where: { $0.id == id }) { TripDetail(trip: t) }
        }
    }
}

struct TripDetail: View {
    @Environment(GameState.self) private var state
    let trip: Trip

    var body: some View {
        List {
            Section {
                MapDrawing(places: state.story.places, highlight: trip.stops)
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                LabeledContent(T("Jour", "Day"), value: trip.day)
                LabeledContent(T("Heure", "Time"), value: trip.time)
                LabeledContent(T("Trajet", "Route"), value: trip.stops.compactMap { id in state.story.places.first { $0.id == id }?.name }.joined(separator: " → "))
            }
            Section(T("Activité", "Activity")) {
                LabeledContent(T("Pas", "Steps"), value: "\(trip.steps)")
                    .foregroundStyle(trip.steps == 0 ? Color.orange : Color.primary)
                if !trip.detail.isEmpty { Text(trip.detail).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(trip.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            state.set("seen_trip_" + trip.id)
            if trip.steps == 0 { state.set("seen_steps") }
        }
    }
}

/// Une carte dessinée : la terre, l'estuaire, la voie ferrée, les lieux.
struct MapDrawing: View {
    let places: [MapPlace]
    let highlight: [String]

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let pts = highlight.compactMap { id in places.first { $0.id == id } }.map { CGPoint(x: $0.point.x * w, y: $0.point.y * h) }
            ZStack {
                Color(red: 0.93, green: 0.92, blue: 0.86)
                // L'océan à gauche, l'estuaire de la Loire
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 0))
                    p.addLine(to: CGPoint(x: w * 0.12, y: 0))
                    p.addCurve(to: CGPoint(x: w * 0.08, y: h), control1: CGPoint(x: w * 0.2, y: h * 0.4), control2: CGPoint(x: w * 0.02, y: h * 0.6))
                    p.addLine(to: CGPoint(x: 0, y: h))
                    p.closeSubpath()
                }
                .fill(Color(red: 0.62, green: 0.8, blue: 0.93))
                Path { p in
                    p.move(to: CGPoint(x: w * 0.14, y: h * 0.62))
                    p.addCurve(to: CGPoint(x: w, y: h * 0.7), control1: CGPoint(x: w * 0.4, y: h * 0.8), control2: CGPoint(x: w * 0.7, y: h * 0.55))
                }
                .stroke(Color(red: 0.62, green: 0.8, blue: 0.93), lineWidth: h * 0.06)
                // La voie ferrée, en pointillés
                Path { p in
                    let all = places.map { CGPoint(x: $0.point.x * w, y: $0.point.y * h) }.sorted { $0.x < $1.x }
                    guard let first = all.first else { return }
                    p.move(to: first)
                    for q in all.dropFirst() { p.addLine(to: q) }
                }
                .stroke(Color(white: 0.55), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                // Le trajet choisi
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    for q in pts.dropFirst() { p.addLine(to: q) }
                }
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                ForEach(places) { pl in
                    let on = highlight.contains(pl.id)
                    VStack(spacing: 2) {
                        Circle().fill(on ? Color.blue : Color(white: 0.5)).frame(width: on ? 12 : 8)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        Text(pl.name)
                            .font(.system(size: 10, weight: on ? .bold : .medium))
                            .foregroundStyle(Color(white: 0.2))
                            .fixedSize()
                    }
                    .position(x: pl.point.x * w, y: pl.point.y * h + 8)
                }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

// MARK: Météo+

struct WeatherApp: View {
    @Environment(GameState.self) private var state

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 4) {
                    Text("Nantes").font(.title.weight(.semibold))
                    Text("11°").font(.system(size: 80, weight: .thin))
                    Text(T("Averses · Max. 13° Min. 7°", "Showers · H 13° L 7°")).foregroundStyle(.white.opacity(0.85))
                }
                .padding(.top, 20)
                VStack(spacing: 0) {
                    ForEach(Array(zip([T("Auj.", "Today"), T("Mer.", "Wed"), T("Jeu.", "Thu"), T("Ven.", "Fri"), T("Sam.", "Sat")],
                                      ["cloud.rain.fill", "cloud.sun.fill", "cloud.fill", "sun.max.fill", "cloud.drizzle.fill"]).enumerated()), id: \.offset) { i, d in
                        HStack {
                            Text(d.0).frame(width: 60, alignment: .leading)
                            Image(systemName: d.1).symbolRenderingMode(.multicolor).frame(width: 40)
                            Spacer()
                            Text("\(7 + i % 3)°").foregroundStyle(.white.opacity(0.7))
                            Capsule().fill(LinearGradient(colors: [.cyan, .yellow], startPoint: .leading, endPoint: .trailing)).frame(width: 90, height: 5)
                            Text("\(12 + i % 3)°")
                        }
                        .padding(.vertical, 10)
                        if i < 4 { Divider().background(Color.white.opacity(0.3)) }
                    }
                }
                .padding(.horizontal, 16)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.15)))

                Button {
                    state.set("seen_weather_share")
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text(state.has("seen_weather_share")
                             ? T("Partage de position actif · 1 appareil : « H »", "Location sharing on · 1 device: \"H\"")
                             : T("Partage actif · 1 appareil", "Sharing on · 1 device"))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(state.has("seen_weather_share") ? 0.95 : 0.45))
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }
            .padding(16)
            .foregroundStyle(.white)
        }
        .background(LinearGradient(colors: [Color(red: 0.3, green: 0.45, blue: 0.7), Color(red: 0.45, green: 0.55, blue: 0.75)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }
}

// MARK: Réglages

struct SettingsApp: View {
    @Environment(GameState.self) private var state

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(get: { state.has("airplane") }, set: { on in state.setAirplane(on) })) {
                    Label(T("Mode avion", "Airplane Mode"), systemImage: "airplane")
                }
                .disabled(state.chapter < 4)
                Label("Wi-Fi", systemImage: "wifi").badge(T("Non connecté", "Not connected"))
                Label("Bluetooth", systemImage: "dot.radiowaves.left.and.right").badge(T("Oui", "On"))
            }
            Section {
                NavigationLink(value: "battery") { Label(T("Batterie", "Battery"), systemImage: "battery.25") }
                NavigationLink(value: "location") { Label(T("Confidentialité · Position", "Privacy · Location"), systemImage: "location.fill") }
            }
            Section(T("Applis", "Apps")) {
                ForEach(state.story.usage) { u in
                    NavigationLink(value: "app_" + u.id) { Label(u.name, systemImage: u.symbol) }
                }
            }
        }
        .navigationDestination(for: String.self) { id in
            switch id {
            case "battery": BatteryView()
            case "location": LocationView()
            default:
                if let u = state.story.usage.first(where: { "app_" + $0.id == id }) { AppUsageDetail(usage: u) }
            }
        }
    }
}

struct BatteryView: View {
    @Environment(GameState.self) private var state

    var body: some View {
        List {
            Section {
                HStack {
                    Text(T("Niveau de la batterie", "Battery level"))
                    Spacer()
                    Text("23 %").foregroundStyle(.orange)
                }
            }
            Section(T("Utilisation par appli (3 derniers jours)", "Usage by app (last 3 days)")) {
                ForEach(state.story.usage.sorted { $0.battery > $1.battery }) { u in
                    NavigationLink(value: "app_" + u.id) {
                        HStack {
                            Label(u.name, systemImage: u.symbol)
                            Spacer()
                            Text("\(u.battery) %").foregroundStyle(u.battery >= 30 ? Color.orange : Color.secondary).monospacedDigit()
                        }
                    }
                }
            }
        }
        .navigationTitle(T("Batterie", "Battery"))
    }
}

struct LocationView: View {
    @Environment(GameState.self) private var state

    var body: some View {
        List {
            Section(footer: Text(T("Les applis qui ont accès à la position de ce téléphone.", "Apps that can access this phone's location."))) {
                ForEach(state.story.usage) { u in
                    NavigationLink(value: "app_" + u.id) {
                        HStack {
                            Label(u.name, systemImage: u.symbol)
                            Spacer()
                            Text(u.location).foregroundStyle(u.spy ? Color.orange : Color.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(T("Position", "Location"))
    }
}

struct AppUsageDetail: View {
    @Environment(GameState.self) private var state
    let usage: AppUsage

    var body: some View {
        List {
            Section {
                LabeledContent(T("Position", "Location"), value: usage.location)
                LabeledContent(T("Batterie", "Battery"), value: "\(usage.battery) %")
            }
            if !usage.details.isEmpty {
                Section {
                    ForEach(usage.details, id: \.self) { line in
                        Text(line).foregroundStyle(usage.spy ? Color.orange : Color.primary)
                    }
                }
            }
            if usage.spy && state.chapter >= 4 {
                Section {
                    Button(role: .destructive) {
                        state.set("spy_off")
                    } label: {
                        Label(state.has("spy_off") ? T("Partage coupé", "Sharing stopped") : T("Arrêter le partage de position", "Stop sharing location"),
                              systemImage: "location.slash.fill")
                    }
                    .disabled(state.has("spy_off"))
                }
            }
        }
        .navigationTitle(usage.name)
        .onAppear { if usage.spy { state.set("spy_found") } }
    }
}
