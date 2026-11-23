// MapView.swift — Vicefold
//
// La carte : la nôtre (dessinée ici) ou la tienne (une capture de la carte du jeu que tu importes, calée sur la nôtre).
// Filtres par catégorie, recherche, lieux visités, épingles perso (nom, note, icône, couleur).
// Sur le Duo : la liste d'un côté du pli, la carte de l'autre. Sur iPhone : la carte, et la liste en feuille.

import PhotosUI
import SwiftUI

@MainActor @Observable
final class MapState {
    var zoom: CGFloat = 1
    var pan: CGSize = .zero
    var layers: Set<VFPlaceKind> = VFPlaceKind.defaultLayers
    var showPins = true
    var selectedPlace: VFPlace?
    var selectedPin: VFPin?
    var dropping = false
    var calibrating = false
    var query = ""
    var hideVisited = false
    /// Une demande de centrer la carte sur un point (coordonnées de la carte).
    var focus: CGPoint?
    /// Glisser jusqu'au point (la carte) ou y être tout de suite (les aperçus).
    var animateFocus = true
}

struct MapTab: View {
    @State private var state = MapState()

    var body: some View {
        DualLayout {
            MapPrimary()
        } secondary: {
            NavigationStack { MapCanvasScreen() }
        }
        .environment(state)
        .onChange(of: AppRouter.shared.mapPlace) { _, p in open(p) }
        .onAppear {
            open(AppRouter.shared.mapPlace)
            // Vice City et Vice Beach, pour les captures.
            if ShotMode.route == "mappins" { state.zoom = 3; state.focus = CGPoint(x: 0.8 * Leonida.size.width, y: 0.5 * Leonida.size.height) }
        }
    }
}

extension MapTab {
    /// Un lieu demandé depuis un autre écran (le lieu du jour…) : on y va, et on l'ouvre.
    fileprivate func open(_ p: VFPlace?) {
        guard let p else { return }
        AppRouter.shared.mapPlace = nil
        state.layers.insert(p.kind)
        state.selectedPlace = p
        state.zoom = max(state.zoom, 6)
        state.focus = CGPoint(x: p.x * Leonida.size.width, y: p.y * Leonida.size.height)
    }
}

/// Étroit : la carte. Large : la liste (la carte est de l'autre côté).
private struct MapPrimary: View {
    @Environment(\.vfWide) private var wide
    var body: some View {
        if wide { NavigationStack { PlaceList() } } else { NavigationStack { MapCanvasScreen(showsListButton: true) } }
    }
}

struct MapCanvasScreen: View {
    var showsListButton = false
    @Environment(MapState.self) private var state
    @Environment(Progress.self) private var progress
    @Environment(Store.self) private var store
    @State private var showList = false
    @State private var showLayers = false
    @State private var showImport = false
    @State private var showPro = false

    var body: some View {
        @Bindable var state = state
        LeonidaMapView(showsCredit: false)
            .ignoresSafeArea(edges: .bottom)
            // Le crédit de la carte reste dans la zone sûre : jamais sous la barre d'onglets.
            .overlay(alignment: .bottomLeading) { if !state.dropping && state.selectedPlace == nil { MapCredit().padding(.leading, 10).padding(.bottom, 6) } }
            .navigationTitle("Leonida")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsListButton {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showList = true } label: { Image(systemName: "list.bullet") }.accessibilityLabel("Places")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showLayers = true } label: { Image(systemName: "square.3.layers.3d") }.accessibilityLabel("Layers")
                    Button {
                        if progress.canAddPin { state.dropping.toggle() } else { showPro = true }
                    } label: { Image(systemName: state.dropping ? "mappin.slash" : "mappin.and.ellipse") }
                        .accessibilityLabel("Add a pin")
                }
            }
            .overlay(alignment: .top) {
                if !state.dropping && !state.calibrating { QuickFilters() }
            }
            .overlay(alignment: .top) {
                if state.dropping {
                    hint("Tap the map where you want your pin")
                } else if state.calibrating {
                    VStack(spacing: 8) {
                        hint("Drag and pinch your map until it lines up with the map below")
                        Button("Done") { state.calibrating = false }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .overlay(alignment: .bottom) { selectionCard }
            .sheet(isPresented: $showList) { NavigationStack { PlaceList(onPick: { showList = false }) }.presentationDetents([.medium, .large]) }
            .sheet(isPresented: $showLayers) { NavigationStack { LayersView(showImport: $showImport) }.presentationDetents([.medium, .large]) }
            .sheet(isPresented: $showPro) { ProView() }
            .sheet(item: $state.selectedPin) { pin in NavigationStack { PinEditor(pin: pin) } }
    }

    private func hint(_ t: LocalizedStringKey) -> some View {
        Text(t).font(.subheadline.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 10)
            .background(.thinMaterial, in: .capsule).padding(.top, 8)
    }

    @ViewBuilder private var selectionCard: some View {
        if let p = state.selectedPlace {
            PlaceCard(place: p) { state.selectedPlace = nil }
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct PlaceCard: View {
    var place: VFPlace
    var close: () -> Void
    @Environment(Progress.self) private var progress
    @State private var showPro = false

    var body: some View {
        let hidden = progress.hidden(place.spoiler)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: place.kind.icon).foregroundStyle(.white).frame(width: 40, height: 40).background(MapColors.color(place.kind), in: .circle)
            VStack(alignment: .leading, spacing: 4) {
                Text(hidden ? String(localized: "Hidden place") : place.name).font(.headline)
                HStack(spacing: 6) {
                    Text(place.kind.title)
                    if let r = place.region { Text("· \(r)") }
                }
                .font(.caption).foregroundStyle(.secondary)
                if !hidden, let n = place.note { Text(n).font(.subheadline).fixedSize(horizontal: false, vertical: true) }
                if !hidden {
                    if let r = place.real {
                        Label { Text("Inspired by \(r)") } icon: { Image(systemName: "globe.americas.fill") }
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if place.enterable == true {
                        Label("You can go inside", systemImage: "door.left.hand.open").font(.caption).foregroundStyle(.secondary)
                    }
                    if place.uncertain == true {
                        Label("Name or place not confirmed yet", systemImage: "questionmark.circle").font(.caption).foregroundStyle(.secondary)
                    }
                    if place.closed == true {
                        Label("Closed", systemImage: "lock").font(.caption).foregroundStyle(.secondary)
                    }
                    if place.community, let url = URL(string: "https://map.gtadb.org/#VI," + place.id.dropFirst(2)) {
                        Link(destination: url) {
                            Label("Photos on GTADB.org", systemImage: "photo.on.rectangle.angled").font(.caption.weight(.semibold))
                        }
                        Text("Source: GTADB.org community (CC BY 4.0)").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Button {
                    if !progress.toggleVisited(place) { showPro = true }
                } label: {
                    Label(progress.visited(place) ? "Visited" : "Mark as visited", systemImage: progress.visited(place) ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.bordered)
                .tint(progress.visited(place) ? VF.teal : VF.coral)
            }
            Spacer(minLength: 0)
            Button(action: close) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary) }
                .accessibilityLabel("Close")
        }
        .padding()
        .frame(maxWidth: 520)
        .background(.regularMaterial, in: .rect(cornerRadius: 22))
        .sheet(isPresented: $showPro) { ProView() }
    }
}

enum MapColors {
    static func color(_ k: VFPlaceKind) -> Color {
        switch k {
        case .region: return .gray
        case .landmark: return VF.magenta
        case .shop: return .blue
        case .property: return .green
        case .activity: return VF.teal
        case .collectible: return VF.sun
        case .event: return .orange
        case .mission: return VF.coral
        case .service: return .purple
        case .hotel: return Color(red: 0.86, green: 0.2, blue: 0.45)
        case .food: return Color(red: 0.95, green: 0.55, blue: 0.1)
        case .gas: return Color(red: 0.85, green: 0.3, blue: 0.2)
        case .transport: return Color(red: 0.2, green: 0.45, blue: 0.85)
        case .nature: return Color(red: 0.2, green: 0.6, blue: 0.3)
        case .civic: return Color(red: 0.45, green: 0.4, blue: 0.7)
        case .other: return .gray
        }
    }
}

/// La carte elle-même : glisser pour se déplacer, pincer pour zoomer, toucher deux fois pour zoomer.
struct LeonidaMapView: View {
    var showsCredit = true
    @Environment(MapState.self) private var state
    @Environment(ContentStore.self) private var content
    @Environment(Progress.self) private var progress
    @Environment(Store.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale
    @State private var dragStart: CGSize?
    @State private var zoomStart: (zoom: CGFloat, pan: CGSize)?
    @State private var fitStart: VFMapFit?
    @State private var myMap: UIImage?

    var body: some View {
        GeometryReader { geo in
            let s0 = min(geo.size.width / Leonida.size.width, geo.size.height / Leonida.size.height)
            let s = s0 * state.zoom
            let center = CGPoint(x: geo.size.width / 2 + state.pan.width, y: geo.size.height / 2 + state.pan.height)
            let toScreen: (CGPoint) -> CGPoint = { m in
                CGPoint(x: center.x + (m.x - Leonida.size.width / 2) * s, y: center.y + (m.y - Leonida.size.height / 2) * s)
            }
            let toMap: (CGPoint) -> CGPoint = { v in
                CGPoint(x: Leonida.size.width / 2 + (v.x - center.x) / s, y: Leonida.size.height / 2 + (v.y - center.y) / s)
            }
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    var c = ctx
                    c.translateBy(x: center.x - Leonida.size.width / 2 * s, y: center.y - Leonida.size.height / 2 * s)
                    c.scaleBy(x: s, y: s)
                    let a = toMap(.zero), b = toMap(CGPoint(x: size.width, y: size.height))
                    let visible = CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
                    Leonida.draw(&c, visible: visible, level: Leonida.level(pointsPerMeter: s, scale: displayScale), dark: scheme == .dark)
                    // Ta carte à toi (Pro), par-dessus, calée une fois pour toutes.
                    if progress.data.customMap, store.isPro, let img = myMap {
                        let f = progress.data.mapFit
                        let w = Leonida.size.width * f.scale
                        let h = w * img.size.height / max(1, img.size.width)
                        let r = CGRect(x: Leonida.size.width / 2 - w / 2 + f.x, y: Leonida.size.height / 2 - h / 2 + f.y, width: w, height: h)
                        var m = c
                        if state.calibrating { m.opacity = 0.55 }
                        m.draw(Image(uiImage: img), in: r)
                    }
                }
                ForEach(markers(toScreen: toScreen, size: geo.size)) { mk in
                    PlaceMarker(place: mk.place, selected: state.selectedPlace == mk.place, visited: progress.visited(mk.place),
                                hidden: progress.hidden(mk.place.spoiler), zoom: state.zoom)
                        .position(mk.point)
                        .onTapGesture { withAnimation(.snappy) { state.selectedPlace = mk.place } }
                }
                if state.showPins {
                    ForEach(progress.data.pins) { pin in
                        PinMarker(pin: pin)
                            .position(toScreen(CGPoint(x: pin.x * Leonida.size.width, y: pin.y * Leonida.size.height)))
                            .onTapGesture { state.selectedPin = pin }
                    }
                }
            }
            .contentShape(.rect)
            .gesture(SpatialTapGesture(count: 2).onEnded { v in zoom(at: v.location, by: 2, geo: geo, s0: s0) })
            .simultaneousGesture(SpatialTapGesture().onEnded { v in tapped(at: toMap(v.location)) })
            .gesture(drag)
            .simultaneousGesture(magnify(geo: geo, s0: s0))
            .onChange(of: state.focus) { _, f in
                guard let f else { return }
                withAnimation(state.animateFocus ? .snappy : nil) {
                    state.zoom = max(state.zoom, 2.2)
                    let s = s0 * state.zoom
                    state.pan = CGSize(width: -(f.x - Leonida.size.width / 2) * s, height: -(f.y - Leonida.size.height / 2) * s)
                }
                state.focus = nil
            }
            .onAppear { if let f = state.focus { state.focus = nil; DispatchQueue.main.async { state.focus = f } } }
        }
        .overlay(alignment: .bottomLeading) { if showsCredit { MapCredit().padding(8) } }
        .clipped()
        .task(id: progress.data.customMap) { myMap = UIImage(contentsOfFile: progress.mapURL.path) }
        .accessibilityLabel("Map of Leonida")
    }

    private var visiblePlaces: [VFPlace] {
        content.content.places.filter { p in
            guard p.kind != .region, state.layers.contains(p.kind) else { return false }
            if p.kind.pro && !store.isPro { return false }
            if state.hideVisited && progress.visited(p) { return false }
            return true
        }
    }

    /// Les repères à l'écran, sans qu'ils se chevauchent : les plus importants d'abord (nos lieux, les lieux où l'on
    /// peut entrer, les monuments…), un seul par case ; on en voit plus en zoomant.
    struct Marker: Identifiable {
        var place: VFPlace
        var point: CGPoint
        var id: String { place.id }
    }

    private func markers(toScreen: (CGPoint) -> CGPoint, size: CGSize) -> [Marker] {
        let cell: CGFloat = state.zoom > 6 ? 56 : 34
        var taken = Set<Int>()
        var out: [Marker] = []
        let sorted = visiblePlaces.sorted { a, b in
            if (a == state.selectedPlace) != (b == state.selectedPlace) { return a == state.selectedPlace }
            return a.rank < b.rank
        }
        for p in sorted {
            let pt = toScreen(CGPoint(x: p.x * Leonida.size.width, y: p.y * Leonida.size.height))
            guard pt.x > -20, pt.y > -20, pt.x < size.width + 20, pt.y < size.height + 20 else { continue }
            let key = Int(floor(pt.x / cell)) &* 4099 &+ Int(floor(pt.y / cell))
            if taken.contains(key) && p != state.selectedPlace { continue }
            taken.insert(key)
            out.append(Marker(place: p, point: pt))
            if out.count >= 140 { break }
        }
        return out
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in
                if state.calibrating {
                    let f = fitStart ?? progress.data.mapFit
                    if fitStart == nil { fitStart = f }
                    let k = 1 / max(0.01, state.zoom) * (Leonida.size.width / 400)
                    progress.edit { d in d.mapFit.x = f.x + v.translation.width * k / 2.5; d.mapFit.y = f.y + v.translation.height * k / 2.5 }
                    return
                }
                let start = dragStart ?? state.pan
                if dragStart == nil { dragStart = start }
                state.pan = CGSize(width: start.width + v.translation.width, height: start.height + v.translation.height)
            }
            .onEnded { _ in dragStart = nil; fitStart = nil }
    }

    private func magnify(geo: GeometryProxy, s0: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { v in
                if state.calibrating {
                    let f = fitStart ?? progress.data.mapFit
                    if fitStart == nil { fitStart = f }
                    progress.edit { $0.mapFit.scale = max(0.3, min(4, f.scale * v.magnification)) }
                    return
                }
                let start = zoomStart ?? (state.zoom, state.pan)
                if zoomStart == nil { zoomStart = start }
                let newZoom = max(1, min(Self.maxZoom, start.zoom * v.magnification))
                let a = CGPoint(x: v.startLocation.x - geo.size.width / 2, y: v.startLocation.y - geo.size.height / 2)
                let k = newZoom / start.zoom
                state.zoom = newZoom
                state.pan = CGSize(width: a.x - (a.x - start.pan.width) * k, height: a.y - (a.y - start.pan.height) * k)
            }
            .onEnded { _ in zoomStart = nil; fitStart = nil }
    }

    private func zoom(at loc: CGPoint, by f: CGFloat, geo: GeometryProxy, s0: CGFloat) {
        let newZoom = state.zoom >= Self.maxZoom * 0.75 ? 1 : min(Self.maxZoom, state.zoom * f)
        let a = CGPoint(x: loc.x - geo.size.width / 2, y: loc.y - geo.size.height / 2)
        let k = newZoom / state.zoom
        withAnimation(.snappy) {
            state.pan = newZoom == 1 ? .zero : CGSize(width: a.x - (a.x - state.pan.width) * k, height: a.y - (a.y - state.pan.height) * k)
            state.zoom = newZoom
        }
    }

    static let maxZoom: CGFloat = 14

    private func tapped(at m: CGPoint) {
        guard state.dropping else {
            if state.selectedPlace != nil { withAnimation(.snappy) { state.selectedPlace = nil } }
            return
        }
        state.dropping = false
        let pin = VFPin(name: String(localized: "My pin"), x: Double(m.x / Leonida.size.width), y: Double(m.y / Leonida.size.height))
        progress.add(pin)
        state.selectedPin = pin
    }
}

struct PlaceMarker: View {
    var place: VFPlace
    var selected: Bool
    var visited: Bool
    var hidden: Bool
    var zoom: CGFloat

    var body: some View {
        let size: CGFloat = selected ? 34 : (zoom > 2 ? 26 : 20)
        VStack(spacing: 2) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: hidden ? "questionmark" : place.kind.icon)
                    .font(.system(size: size * 0.48, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(MapColors.color(place.kind).opacity(visited ? 0.45 : 1), in: .circle)
                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                if visited {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(.white, VF.teal).offset(x: 4, y: -4)
                }
            }
            if zoom > 6 || selected {
                Text(hidden ? "?" : place.name)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 4)
                    .background(.thinMaterial, in: .capsule)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hidden ? String(localized: "Hidden place") : place.name)
        .accessibilityAddTraits(.isButton)
    }
}

struct PinMarker: View {
    var pin: VFPin
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: pin.icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(VFPin.colors[pin.color % VFPin.colors.count], in: .circle)
                .overlay(Circle().stroke(.white, lineWidth: 2))
            Triangle().fill(VFPin.colors[pin.color % VFPin.colors.count]).frame(width: 10, height: 7)
        }
        .offset(y: -18)
        .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
        .accessibilityLabel(pin.name)
        .accessibilityAddTraits(.isButton)
    }
}

private struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// La liste des lieux et des épingles, avec la recherche.
struct PlaceList: View {
    var onPick: (() -> Void)?
    @Environment(MapState.self) private var state
    @Environment(ContentStore.self) private var content
    @Environment(Progress.self) private var progress
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var state = state
        List {
            if !progress.data.pins.isEmpty {
                Section("My pins") {
                    ForEach(progress.data.pins.filter { matches($0.name) }) { pin in
                        Button { go(pin.x, pin.y); state.selectedPin = pin } label: {
                            HStack {
                                PinMarker(pin: pin).offset(y: 18).frame(width: 34, height: 34).scaleEffect(0.8)
                                VStack(alignment: .leading) {
                                    Text(pin.name).foregroundStyle(.primary)
                                    if !pin.note.isEmpty { Text(pin.note).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                }
                            }
                        }
                    }
                    .onDelete { idx in
                        let list = progress.data.pins.filter { matches($0.name) }
                        for i in idx { progress.remove(list[i]) }
                    }
                }
            }
            ForEach(VFPlaceKind.allCases.filter { $0 != .region }) { kind in
                let items = content.content.places.filter { $0.kind == kind && matches($0.name) && !(state.hideVisited && progress.visited($0)) }
                if !items.isEmpty {
                    Section {
                        if kind.pro && !store.isPro {
                            Label("\(items.count) places with Pro", systemImage: "lock.fill").foregroundStyle(.secondary)
                        } else {
                            ForEach(items) { p in
                                Button {
                                    go(p.x, p.y)
                                    state.selectedPlace = p
                                } label: {
                                    HStack {
                                        Image(systemName: kind.icon).foregroundStyle(MapColors.color(kind)).frame(width: 26)
                                        VStack(alignment: .leading) {
                                            Text(progress.hidden(p.spoiler) ? String(localized: "Hidden place") : p.name).foregroundStyle(.primary)
                                            if let r = p.region { Text(r).font(.caption).foregroundStyle(.secondary) }
                                        }
                                        Spacer()
                                        if progress.visited(p) { Image(systemName: "checkmark.circle.fill").foregroundStyle(VF.teal) }
                                    }
                                }
                            }
                        }
                    } header: {
                        Text(kind.title)
                    }
                }
            }
        }
        .searchable(text: $state.query, prompt: Text("Search places and pins"))
        .navigationTitle("Places")
        .scrollContentBackground(.hidden)
        .background(VFBackdrop())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $state.hideVisited) { Image(systemName: "eye.slash") }
                    .toggleStyle(.button)
                    .accessibilityLabel("Hide visited")
            }
        }
    }

    private func matches(_ s: String) -> Bool {
        state.query.isEmpty || s.localizedCaseInsensitiveContains(state.query)
    }

    private func go(_ x: Double, _ y: Double) {
        state.focus = CGPoint(x: x * Leonida.size.width, y: y * Leonida.size.height)
        onPick?()
    }
}

/// Les couches de la carte, et ta propre carte.
struct LayersView: View {
    @Binding var showImport: Bool
    @Environment(MapState.self) private var state
    @Environment(Progress.self) private var progress
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var item: PhotosPickerItem?
    @State private var showPro = false

    var body: some View {
        @Bindable var state = state
        List {
            Section("Layers") {
                ForEach(VFPlaceKind.allCases.filter { $0 != .region }) { k in
                    Toggle(isOn: Binding(get: { state.layers.contains(k) }, set: { on in if on { state.layers.insert(k) } else { state.layers.remove(k) } })) {
                        HStack {
                            Label(k.title, systemImage: k.icon)
                            if k.pro && !store.isPro { Spacer(); Text("Pro").font(.caption.bold()).foregroundStyle(VF.coral) }
                        }
                    }
                    .disabled(k.pro && !store.isPro)
                }
                Toggle(isOn: $state.showPins) { Label("My pins", systemImage: "mappin") }
                Toggle(isOn: $state.hideVisited) { Label("Hide visited places", systemImage: "eye.slash") }
            }
            Section {
                if store.isPro {
                    PhotosPicker(selection: $item, matching: .images) {
                        Label(progress.data.customMap ? "Replace my map" : "Import my map", systemImage: "photo.on.rectangle")
                    }
                    if progress.data.customMap {
                        Toggle("Use my map", isOn: Binding(get: { progress.data.customMap }, set: { v in progress.edit { $0.customMap = v } }))
                        Button { state.calibrating = true; dismiss() } label: { Label("Line it up with the map", systemImage: "arrow.up.and.down.and.arrow.left.and.right") }
                        Button(role: .destructive) {
                            try? FileManager.default.removeItem(at: progress.mapURL)
                            progress.edit { $0.customMap = false; $0.mapFit = VFMapFit() }
                        } label: { Label("Remove my map", systemImage: "trash") }
                    }
                } else {
                    Button { showPro = true } label: { Label("Import my map (Pro)", systemImage: "lock.fill") }
                }
            } header: {
                Text("Your own map")
            } footer: {
                Text("Take a screenshot of the full map in your game (or a photo of the paper map), import it here, then line it up once. Your pins and places then sit on your real map. The picture stays on this iPhone.")
            }
        }
        .navigationTitle("Map")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .sheet(isPresented: $showPro) { ProView() }
        .onChange(of: item) { _, it in
            guard let it else { return }
            Task {
                if let data = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: data),
                   let jpg = img.jpegData(compressionQuality: 0.9) {
                    try? jpg.write(to: progress.mapURL, options: .atomic)
                    progress.edit { $0.customMap = true; $0.mapFit = VFMapFit() }
                    state.calibrating = true
                    dismiss()
                }
            }
        }
    }
}

/// Une épingle : nom, note, icône, couleur.
struct PinEditor: View {
    @State var pin: VFPin
    @Environment(Progress.self) private var progress
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $pin.name)
                TextField("Note", text: $pin.note, axis: .vertical).lineLimit(2...6)
            }
            Section("Icon") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                    ForEach(VFPin.icons, id: \.self) { i in
                        Button { pin.icon = i } label: {
                            Image(systemName: i).frame(width: 40, height: 40)
                                .background(pin.icon == i ? VFPin.colors[pin.color].opacity(0.3) : Color.clear, in: .circle)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Section("Color") {
                HStack {
                    ForEach(VFPin.colors.indices, id: \.self) { c in
                        Button { pin.color = c } label: {
                            Circle().fill(VFPin.colors[c]).frame(width: 30, height: 30)
                                .overlay(Circle().stroke(.primary, lineWidth: pin.color == c ? 2 : 0).padding(-3))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Section {
                Button("Delete pin", role: .destructive) { progress.remove(pin); dismiss() }
            }
        }
        .navigationTitle("Pin")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Save") { progress.update(pin); dismiss() } }
        }
    }
}

/// Le crédit de la carte (licence CC BY 4.0) : toujours visible, touche pour les détails.
struct MapCredit: View {
    @State private var show = false
    var body: some View {
        Button { show = true } label: {
            Text("Map © GTADB.org · Yanis · CC BY 4.0")
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(.thinMaterial, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Map credits")
        .sheet(isPresented: $show) { NavigationStack { MapCreditView() }.presentationDetents([.medium]) }
    }
}

struct MapCreditView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            Section {
                Text("The map is the GTA VI Community Map v18, drawn by Yanis and the GTA mapping community, from the tiles of GTADB.org. Places come from the GTADB.org landmarks. Both are shared under the Creative Commons Attribution 4.0 license. We cropped the map to Leonida and grouped the places into layers.")
                Text("It's a fan map, not Rockstar's, and it keeps improving.").foregroundStyle(.secondary)
            }
            Section {
                Link("map.gtadb.org", destination: Leonida.sourceURL)
                Link("Creative Commons Attribution 4.0", destination: Leonida.licenseURL)
            }
        }
        .navigationTitle("Map credits")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

/// Les filtres rapides, en verre, au-dessus de la carte : un geste pour ne voir que les hôtels, les stations-service…
/// Toucher à nouveau le même filtre remet toutes les couches.
struct QuickFilters: View {
    @Environment(MapState.self) private var state
    @Environment(Store.self) private var store
    private let kinds: [VFPlaceKind] = [.landmark, .hotel, .food, .shop, .gas, .transport, .nature, .activity]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(kinds) { k in
                        let on = state.layers == [k]
                        Button {
                            withAnimation(.snappy) { state.layers = on ? VFPlaceKind.defaultLayers : [k] }
                        } label: {
                            Label(k.title, systemImage: k.icon)
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .foregroundStyle(on ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(on ? .regular.tint(MapColors.color(k)).interactive() : .regular.interactive(), in: .capsule)
                        .disabled(k.pro && !store.isPro)
                        .opacity(k.pro && !store.isPro ? 0.5 : 1)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.top, 6)
    }
}
