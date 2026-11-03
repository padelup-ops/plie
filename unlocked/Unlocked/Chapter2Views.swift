import SwiftUI

// MARK: - Chapitre 2 : l'album masqué, la voiture grise, l'agenda

struct HiddenAlbumView: View {
    @Environment(GameState.self) private var state
    @State private var code = ""
    @State private var shake = 0.0
    @State private var hint = -1

    var body: some View {
        if let album = state.story.hiddenAlbum {
            if state.albumOpen {
                ScrollView {
                    if state.carsTotal > 0 {
                        Text(state.has("car_all")
                             ? T("Toujours la même voiture. Toujours la même plaque.", "Always the same car. Always the same plate.")
                             : T("Regarde bien l'arrière-plan de chaque photo.", "Look closely at the background of each photo."))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(state.has("car_all") ? .orange : .secondary)
                            .padding(.top, 8)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 2), spacing: 2) {
                        ForEach(album.photos) { p in
                            NavigationLink(value: p.id) {
                                ArtView(art: p.art)
                                    .overlay {
                                        if let c = p.car {
                                            GeometryReader { g in
                                                GreyCar(plate: "", showPlate: false)
                                                    .frame(width: g.size.width * 0.3, height: g.size.width * 0.15)
                                                    .position(x: c.x * g.size.width, y: c.y * g.size.height)
                                            }
                                        }
                                    }
                                    .overlay(alignment: .topTrailing) {
                                        if state.has("car_" + p.id) {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.orange).padding(6)
                                        }
                                    }
                                    .aspectRatio(1, contentMode: .fill)
                                    .clipped()
                            }
                            .accessibilityLabel(p.date + ", " + p.place)
                        }
                    }
                }
                .navigationTitle(album.title)
            } else {
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: "lock.fill").font(.system(size: 40))
                    Text(T("Album verrouillé", "Locked album")).font(.title2.weight(.bold))
                    Text(T("Saisis le code à 3 chiffres", "Enter the 3-digit code")).foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        ForEach(0..<album.code.count, id: \.self) { i in
                            Text(i < code.count ? String(Array(code)[i]) : "–")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .frame(width: 50, height: 62)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
                        }
                    }
                    .offset(x: shake)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(70), spacing: 14), count: 3), spacing: 12) {
                        ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"], id: \.self) { k in
                            if k.isEmpty {
                                Color.clear.frame(width: 64, height: 54)
                            } else {
                                Button { press(k, album: album) } label: {
                                    Text(k).font(.system(size: 26, weight: .medium))
                                        .frame(width: 64, height: 54)
                                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray5)))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(k == "⌫" ? T("Effacer", "Delete") : k)
                            }
                        }
                    }
                    if hint >= 0 {
                        Text(album.hints[hint])
                            .font(.callout.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }
                    Button {
                        withAnimation { hint = min(hint + 1, album.hints.count - 1) }
                    } label: {
                        Label(T("Indice", "Hint"), systemImage: "lightbulb.fill")
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .navigationTitle(album.title)
            }
        }
    }

    private func press(_ k: String, album: HiddenAlbum) {
        if k == "⌫" { if !code.isEmpty { code.removeLast() }; return }
        guard code.count < album.code.count else { return }
        code += k
        if code.count == album.code.count {
            if !state.tryAlbum(code) {
                withAnimation(.default) { shake = 12 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { withAnimation(.default) { shake = -12 } }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { withAnimation(.default) { shake = 0 } }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { code = "" }
            }
        }
    }
}

/// Une petite voiture grise vue de dos, avec sa plaque.
struct GreyCar: View {
    let plate: String
    let showPlate: Bool

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                RoundedRectangle(cornerRadius: h * 0.25).fill(Color(white: 0.55))
                    .frame(width: w, height: h * 0.6).offset(y: h * 0.12)
                RoundedRectangle(cornerRadius: h * 0.2).fill(Color(white: 0.6))
                    .frame(width: w * 0.62, height: h * 0.45).offset(y: -h * 0.2)
                RoundedRectangle(cornerRadius: h * 0.1).fill(Color(red: 0.55, green: 0.65, blue: 0.75))
                    .frame(width: w * 0.5, height: h * 0.3).offset(y: -h * 0.2)
                Capsule().fill(Color.red.opacity(0.85)).frame(width: w * 0.14, height: h * 0.1).offset(x: -w * 0.36, y: h * 0.1)
                Capsule().fill(Color.red.opacity(0.85)).frame(width: w * 0.14, height: h * 0.1).offset(x: w * 0.36, y: h * 0.1)
                RoundedRectangle(cornerRadius: 2).fill(Color.white)
                    .frame(width: w * 0.36, height: h * 0.16)
                    .overlay(
                        Text(showPlate ? plate : "")
                            .font(.system(size: max(5, h * 0.11), weight: .heavy, design: .monospaced))
                            .foregroundStyle(.black)
                            .minimumScaleFactor(0.3)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.orange, lineWidth: showPlate ? 1.5 : 0))
                    .offset(y: h * 0.22)
                Capsule().fill(Color.black.opacity(0.8)).frame(width: w * 0.18, height: h * 0.16).offset(x: -w * 0.32, y: h * 0.45)
                Capsule().fill(Color.black.opacity(0.8)).frame(width: w * 0.18, height: h * 0.16).offset(x: w * 0.32, y: h * 0.45)
            }
            .frame(width: w, height: h)
        }
        .contentShape(Rectangle())
    }
}

// MARK: Agenda

struct CalendarApp: View {
    @Environment(GameState.self) private var state

    var body: some View {
        let days = state.story.events.reduce(into: [String]()) { if !$0.contains($1.day) { $0.append($1.day) } }
        List {
            ForEach(days, id: \.self) { day in
                Section(day) {
                    ForEach(state.story.events.filter { $0.day == day }) { e in
                        NavigationLink(value: e.id) {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 2).fill(e.color).frame(width: 4, height: 38)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.title).font(.body.weight(.semibold))
                                    Text(e.time).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }

    }
}

struct EventDetail: View {
    @Environment(GameState.self) private var state
    let event: CalendarEvent

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(event.title).font(.title2.weight(.bold))
                    Text(event.day).foregroundStyle(.secondary)
                    Text(event.time).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
            Section {
                LabeledContent(T("Calendrier", "Calendar")) {
                    HStack(spacing: 6) {
                        Circle().fill(event.color).frame(width: 10, height: 10)
                        Text(T("Personnel", "Personal"))
                    }
                }
                LabeledContent(T("Alerte", "Alert"), value: T("30 minutes avant", "30 minutes before"))
            }
            if !event.detail.isEmpty {
                Section(T("Notes", "Notes")) { Text(event.detail) }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { state.set("seen_event_" + event.id) }
    }
}
