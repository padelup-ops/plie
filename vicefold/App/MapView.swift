// MapView.swift — Vicefold
//
// La carte, comme un écran tactique : la carte de fans en hologramme (ou dans ses couleurs d'origine, au choix), un
// quadrillage, des repères lumineux, des filtres en verre et un relevé de position.
// La nôtre (dessinée ici) ou la tienne (une capture de la carte du jeu que tu importes, calée sur la nôtre).
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
    /// La taille de la carte à l'écran (pour le relevé de position).
    var viewSize: CGSize = .zero

    /// Le point de la carte au centre de l'écran, de 0 à 1.
    var center: CGPoint {
        let s0 = min(viewSize.width / Leonida.size.width, viewSize.height / Leonida.size.height)
        guard s0 > 0, zoom > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        let s = s0 * zoom
        return CGPoint(x: 0.5 - pan.width / (s * Leonida.size.width), y: 0.5 - pan.height / (s * Leonida.size.height))
    }
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
            if ShotMode.route == "mappins" || ShotMode.route == "layers" { state.zoom = 3; state.focus = CGPoint(x: 0.8 * Leonida.size.width, y: 0.5 * Leonida.size.height) }
            if ShotMode.route == "place", let p = ContentStore.shared.content.places.first(where: { $0.community && $0.real != nil && $0.kind == .landmark }) { open(p) }
        }
    }
}

extension MapTab {
    /// Un lieu demandé depuis un autre écran (le lieu du jour, la recherche…) : on y va, et on l'ouvre.
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
    @State private var showLayers = ShotMode.route == "layers"
    @State private var showImport = false
    @State private var showPro = false

    var body: some View {
        @Bindable var state = state
        LeonidaMapView(showsCredit: false)
            .ignoresSafeArea(edges: .bottom)
            // Le crédit de la carte et le relevé restent dans la zone sûre : jamais sous la barre d'onglets.
            .overlay(alignment: .bottom) {
                if !state.dropping && state.selectedPlace == nil {
                    HStack(alignment: .bottom) {
                        MapCredit()
                        Spacer(minLength: 8)
                        MapReadout()
                    }
                    .padding(.horizontal, 10).padding(.bottom, 6)
                }
            }
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
                        Button("Done") { state.calibrating = false }.buttonStyle(.vf(.primary, compact: true))
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
        Text(t).font(.subheadline.weight(.semibold)).foregroundStyle(VF.text).multilineTextAlignment(.center)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .vfGlass(in: Capsule(), tint: VF.cyan.opacity(0.25))
            .padding(.top, 8).padding(.horizontal, 16)
    }

    @ViewBuilder private var selectionCard: some View {
        if let p = state.selectedPlace {
            PlaceCard(place: p) { state.selectedPlace = nil }
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// Le relevé de position : le centre de l'écran sur la carte (de 0 à 1) et le zoom.
struct MapReadout: View {
    @Environment(MapState.self) private var state

    var body: some View {
        let c = state.center
        Text(verbatim: String(format: "X %.3f  Y %.3f  ×%.1f", min(1, max(0, c.x)), min(1, max(0, c.y)), state.zoom))
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(VF.cyan)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(VF.ink.opacity(0.82), in: .capsule)
            .overlay(Capsule().stroke(VF.cyan.opacity(0.35), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

struct PlaceCard: View {
    var place: VFPlace
    var close: () -> Void
    @Environment(Progress.self) private var progress
    @State private var showPro = false

    var body: some View {
        let hidden = progress.hidden(place.spoiler)
        let color = MapColors.color(place.kind)
        HStack(alignment: .top, spacing: 12) {
            VFIconBadge(icon: hidden ? "questionmark" : place.kind.icon, color: color, size: 42)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(place.kind.title)
                    if let r = place.region { Text(verbatim: "· \(r)") }
                }
                .font(VF.mono(10)).textCase(.uppercase).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
                Text(hidden ? String(localized: "Hidden place") : place.name).font(VF.display(22, relativeTo: .title3)).foregroundStyle(VF.text)
                    .fixedSize(horizontal: false, vertical: true)
                if !hidden, let n = place.note { Text(n).font(.subheadline).foregroundStyle(VF.text).fixedSize(horizontal: false, vertical: true) }
                if !hidden {
                    if let r = place.real {
                        Label { Text("Inspired by \(r)") } icon: { Image(systemName: "globe.americas.fill") }
                            .font(.caption).foregroundStyle(VF.textDim)
                    }
                    if place.enterable == true {
                        Label("You can go inside", systemImage: "door.left.hand.open").font(.caption).foregroundStyle(VF.textDim)
                    }
                    if place.uncertain == true {
                        Label("Name or place not confirmed yet", systemImage: "questionmark.circle").font(.caption).foregroundStyle(VF.textDim)
                    }
                    if place.closed == true {
                        Label("Closed", systemImage: "lock").font(.caption).foregroundStyle(VF.textDim)
                    }
                    if place.community, let url = URL(string: "https://map.gtadb.org/#VI," + place.id.dropFirst(2)) {
                        Link(destination: url) {
                            Label("Photos on GTADB.org", systemImage: "photo.on.rectangle.angled").font(.caption.weight(.semibold))
                        }
                        .tint(VF.cyan)
                        Text("Source: GTADB.org community (CC BY 4.0)").font(.caption2).foregroundStyle(VF.textFaint)
                    }
                }
                Button {
                    if !progress.toggleVisited(place) { showPro = true }
                } label: {
                    Label(progress.visited(place) ? "Visited" : "Mark as visited", systemImage: progress.visited(place) ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.vf(progress.visited(place) ? .done : .primary, compact: true))
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
            VStack(spacing: 14) {
                Button(action: close) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(VF.textDim) }
                    .accessibilityLabel("Close")
                // Un lieu favori reste toujours visible sur la carte, et en tête de la liste.
                Button { progress.toggleFavorite(place) } label: {
                    Image(systemName: progress.isFavorite(place) ? "star.fill" : "star").font(.title3)
                        .foregroundStyle(progress.isFavorite(place) ? VF.sun : VF.textDim)
                        .shadow(color: progress.isFavorite(place) ? VF.sun.opacity(0.8) : .clear, radius: 5)
                        .frame(width: 30, height: 30)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Favorite")
                .accessibilityAddTraits(progress.isFavorite(place) ? .isSelected : [])
            }
            .buttonStyle(.plain)
        }
        .padding()
        .frame(maxWidth: 520)
        .vfGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .vfTicks(color, length: 10, inset: 7)
        .sheet(isPresented: $showPro) { ProView() }
    }
}

/// Les couleurs des catégories sur la carte : des néons, tous lisibles sur le fond sombre.
enum MapColors {
    static func color(_ k: VFPlaceKind) -> Color {
        switch k {
        case .region: return Color(red: 0.70, green: 0.74, blue: 0.84)
        case .landmark: return VF.flamingo
        case .shop: return VF.sky
        case .property: return VF.palm
        case .activity: return VF.cyan
        case .collectible: return VF.sun
        case .event: return VF.sunset
        case .mission: return Color(red: 1.0, green: 0.38, blue: 0.42)
        case .service: return Color(red: 0.80, green: 0.58, blue: 1.0)
        case .hotel: return Color(red: 1.0, green: 0.55, blue: 0.80)
        case .food: return Color(red: 1.0, green: 0.68, blue: 0.32)
        case .gas: return Color(red: 1.0, green: 0.47, blue: 0.36)
        case .transport: return Color(red: 0.44, green: 0.74, blue: 1.0)
        case .nature: return Color(red: 0.54, green: 0.93, blue: 0.44)
        case .civic: return Color(red: 0.74, green: 0.72, blue: 0.99)
        case .other: return Color(red: 0.66, green: 0.72, blue: 0.84)
        }
    }
}

/// La carte elle-même : glisser pour se déplacer, pincer pour zoomer, toucher deux fois pour zoomer.
struct LeonidaMapView: View {
    var showsCredit = true
    /// Le quadrillage et le vignettage de l'écran tactique (pas sur les aperçus).
    var decorated = true
    @Environment(MapState.self) private var state
    @Environment(ContentStore.self) private var content
    @Environment(Progress.self) private var progress
    @Environment(Store.self) private var store
    @Environment(\.displayScale) private var displayScale
    @AppStorage(Leonida.styleKey) private var original = false
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
                    Leonida.draw(&c, visible: visible, level: Leonida.level(pointsPerMeter: s, scale: displayScale), holo: !original)
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
                    // Le quadrillage : une ligne tous les 1 024 m de la carte, qui suit la carte.
                    if decorated {
                        var grid = Path()
                        var gx: CGFloat = 0
                        while gx <= Leonida.size.width {
                            let x = toScreen(CGPoint(x: gx, y: 0)).x
                            if x >= 0, x <= size.width { grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height)) }
                            gx += 1024
                        }
                        var gy: CGFloat = 0
                        while gy <= Leonida.size.height {
                            let y = toScreen(CGPoint(x: 0, y: gy)).y
                            if y >= 0, y <= size.height { grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y)) }
                            gy += 1024
                        }
                        ctx.stroke(grid, with: .color(VF.cyan.opacity(original ? 0.10 : 0.13)), lineWidth: 0.5)
                    }
                }
                if decorated {
                    RadialGradient(colors: [.clear, VF.abyss.opacity(0.55)], center: .center,
                                   startRadius: min(geo.size.width, geo.size.height) * 0.45, endRadius: max(geo.size.width, geo.size.height) * 0.75)
                        .allowsHitTesting(false)
                }
                ForEach(markers(toScreen: toScreen, size: geo.size)) { mk in
                    PlaceMarker(place: mk.place, selected: state.selectedPlace == mk.place, visited: progress.visited(mk.place),
                                hidden: progress.hidden(mk.place.spoiler), zoom: state.zoom, favorite: progress.isFavorite(mk.place))
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
            .gesture(drag(s0: s0))
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
            .onChange(of: geo.size, initial: true) { _, size in if decorated { state.viewSize = size } }
            .onAppear { if let f = state.focus { state.focus = nil; DispatchQueue.main.async { state.focus = f } } }
        }
        .overlay(alignment: .bottomLeading) { if showsCredit { MapCredit().padding(8) } }
        .clipped()
        .task(id: progress.data.customMap) { myMap = UIImage(contentsOfFile: progress.mapURL.path) }
        .accessibilityLabel("Map of Leonida")
    }

    private var visiblePlaces: [VFPlace] {
        content.content.places.filter { p in
            guard p.kind != .region else { return false }
            if p.kind.pro && !store.isPro { return false }
            // Un lieu favori se voit quelles que soient les couches et les filtres (sur la carte, pas sur les aperçus).
            if decorated && progress.isFavorite(p) { return true }
            guard state.layers.contains(p.kind) else { return false }
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
        // Le lieu choisi d'abord, puis les favoris, puis par importance.
        let places = visiblePlaces
        let favorites = progress.data.favorites.isEmpty ? [] : Set(places.filter { progress.isFavorite($0) }.map(\.id))
        let sorted = places.sorted { a, b in
            if (a == state.selectedPlace) != (b == state.selectedPlace) { return a == state.selectedPlace }
            if favorites.contains(a.id) != favorites.contains(b.id) { return favorites.contains(a.id) }
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

    /// La carte ne sort jamais de l'écran : son bord ne dépasse pas le centre de la vue.
    private func clamped(_ pan: CGSize, zoom: CGFloat, s0: CGFloat) -> CGSize {
        let s = s0 * zoom
        let mx = Leonida.size.width * s / 2, my = Leonida.size.height * s / 2
        return CGSize(width: max(-mx, min(mx, pan.width)), height: max(-my, min(my, pan.height)))
    }

    private func drag(s0: CGFloat) -> some Gesture {
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
                state.pan = clamped(CGSize(width: start.width + v.translation.width, height: start.height + v.translation.height), zoom: state.zoom, s0: s0)
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
                state.pan = clamped(CGSize(width: a.x - (a.x - start.pan.width) * k, height: a.y - (a.y - start.pan.height) * k), zoom: newZoom, s0: s0)
            }
            .onEnded { _ in zoomStart = nil; fitStart = nil }
    }

    private func zoom(at loc: CGPoint, by f: CGFloat, geo: GeometryProxy, s0: CGFloat) {
        let newZoom = state.zoom >= Self.maxZoom * 0.75 ? 1 : min(Self.maxZoom, state.zoom * f)
        let a = CGPoint(x: loc.x - geo.size.width / 2, y: loc.y - geo.size.height / 2)
        let k = newZoom / state.zoom
        withAnimation(.snappy) {
            state.pan = newZoom == 1 ? .zero : clamped(CGSize(width: a.x - (a.x - state.pan.width) * k, height: a.y - (a.y - state.pan.height) * k), zoom: newZoom, s0: s0)
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
        // Une épingle se pose sur la carte, pas dans la mer autour.
        let x = min(1, max(0, Double(m.x / Leonida.size.width))), y = min(1, max(0, Double(m.y / Leonida.size.height)))
        let pin = VFPin(name: String(localized: "My pin"), x: x, y: y)
        progress.add(pin)
        state.selectedPin = pin
    }
}

/// Un repère : un disque sombre cerclé de la couleur de sa catégorie, qui luit ; plein quand il est choisi.
struct PlaceMarker: View {
    var place: VFPlace
    var selected: Bool
    var visited: Bool
    var hidden: Bool
    var zoom: CGFloat
    var favorite = false

    var body: some View {
        let size: CGFloat = selected ? 36 : (favorite ? 28 : (zoom > 2 ? 26 : 20))
        let color = MapColors.color(place.kind)
        VStack(spacing: 3) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: hidden ? "questionmark" : place.kind.icon)
                    .font(.system(size: size * 0.46, weight: .bold))
                    .foregroundStyle(selected ? VF.ink : color.opacity(visited ? 0.6 : 1))
                    .frame(width: size, height: size)
                    .background(selected ? AnyShapeStyle(color) : AnyShapeStyle(VF.ink.opacity(0.9)), in: .circle)
                    .overlay(Circle().stroke(selected ? Color.white : color.opacity(visited ? 0.45 : 1), lineWidth: selected ? 2 : 1.5))
                    .shadow(color: color.opacity(visited ? 0.2 : (selected ? 1 : 0.8)), radius: selected ? 10 : 4)
                if visited {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(VF.ink, VF.palm).offset(x: 4, y: -4)
                }
            }
            .overlay(alignment: .topLeading) {
                if favorite {
                    Image(systemName: "star.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(VF.sun)
                        .shadow(color: .black.opacity(0.8), radius: 1).offset(x: -4, y: -4)
                }
            }
            if zoom > 6 || selected {
                Text(hidden ? "?" : place.name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(VF.text)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(VF.ink.opacity(0.85), in: .capsule)
                    .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 0.5))
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
        let color = VFPin.colors[abs(pin.color) % VFPin.colors.count]
        VStack(spacing: 0) {
            Image(systemName: pin.icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(VF.ink)
                .frame(width: 30, height: 30)
                .background(color, in: .circle)
                .overlay(Circle().stroke(.white, lineWidth: 2))
            Triangle().fill(color).frame(width: 10, height: 7)
        }
        .offset(y: -18)
        .shadow(color: color.opacity(0.85), radius: 6)
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
        let pins = progress.data.pins.filter { matches($0.name) }
        let kinds = VFPlaceKind.allCases.filter { $0 != .region }
        let found = kinds.contains { kind in content.content.places.contains { $0.kind == kind && shown($0) } }
        // Les favoris (jamais un lieu masqué : on ne peut mettre en favori qu'un lieu ouvert sur la carte).
        let favorites = progress.data.favorites.isEmpty ? [] : content.content.places.filter { progress.isFavorite($0) && !progress.hidden($0.spoiler) && matches($0.name) }
        List {
            Group {
                if !pins.isEmpty {
                    Section("My pins") {
                        ForEach(pins) { pin in
                            Button { go(pin.x, pin.y); state.selectedPin = pin } label: {
                                HStack {
                                    PinMarker(pin: pin).offset(y: 18).frame(width: 34, height: 34).scaleEffect(0.8)
                                    VStack(alignment: .leading) {
                                        Text(pin.name).foregroundStyle(VF.text)
                                        if !pin.note.isEmpty { Text(pin.note).font(.caption).foregroundStyle(VF.textDim).lineLimit(1) }
                                    }
                                }
                            }
                        }
                        .onDelete { idx in
                            for i in idx where i < pins.count { progress.remove(pins[i]) }
                        }
                    }
                }
                if !favorites.isEmpty {
                    Section("Favorites") {
                        ForEach(favorites) { p in
                            Button {
                                go(p.x, p.y)
                                state.selectedPlace = p
                            } label: {
                                HStack {
                                    Image(systemName: "star.fill").foregroundStyle(VF.sun).frame(width: 26)
                                        .shadow(color: VF.sun.opacity(0.6), radius: 4)
                                    VStack(alignment: .leading) {
                                        Text(p.name).foregroundStyle(VF.text)
                                        Text(p.region ?? p.kind.title).font(.caption).foregroundStyle(VF.textDim)
                                    }
                                    Spacer()
                                    if progress.visited(p) { Image(systemName: "checkmark.circle.fill").foregroundStyle(VF.palm).accessibilityLabel("Visited") }
                                }
                            }
                        }
                    }
                }
                ForEach(kinds) { kind in
                    let items = content.content.places.filter { $0.kind == kind && shown($0) }
                    if !items.isEmpty {
                        Section {
                            if kind.pro && !store.isPro {
                                Label("\(items.count) places with Pro", systemImage: "lock.fill").foregroundStyle(VF.textDim)
                            } else {
                                ForEach(items) { p in
                                    Button {
                                        go(p.x, p.y)
                                        state.selectedPlace = p
                                    } label: {
                                        HStack {
                                            Image(systemName: kind.icon).foregroundStyle(MapColors.color(kind)).frame(width: 26)
                                                .shadow(color: MapColors.color(kind).opacity(0.6), radius: 4)
                                            VStack(alignment: .leading) {
                                                Text(progress.hidden(p.spoiler) ? String(localized: "Hidden place") : p.name).foregroundStyle(VF.text)
                                                if let r = p.region { Text(r).font(.caption).foregroundStyle(VF.textDim) }
                                            }
                                            Spacer()
                                            if progress.visited(p) { Image(systemName: "checkmark.circle.fill").foregroundStyle(VF.palm).accessibilityLabel("Visited") }
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text(kind.title)
                        }
                    }
                }
                if pins.isEmpty && favorites.isEmpty && !found {
                    // Rien ne correspond : la recherche ou « masquer les lieux visités » a tout retiré.
                    Section {
                        VFEmptyState(icon: "mappin.slash", title: "No place found", message: "Try another name, or show the places you've already visited.")
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .vfRows()
        }
        .searchable(text: $state.query, prompt: Text("Search places and pins"))
        .navigationTitle("Places")
        .vfScreen()
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

    /// Un lieu masqué (spoiler) ne se trouve pas par son vrai nom.
    private func shown(_ p: VFPlace) -> Bool {
        if state.hideVisited && progress.visited(p) { return false }
        if state.query.isEmpty { return true }
        return !progress.hidden(p.spoiler) && p.name.localizedCaseInsensitiveContains(state.query)
    }

    private func go(_ x: Double, _ y: Double) {
        state.focus = CGPoint(x: x * Leonida.size.width, y: y * Leonida.size.height)
        onPick?()
    }
}

/// Les couches de la carte, son style, et ta propre carte.
struct LayersView: View {
    @Binding var showImport: Bool
    @Environment(MapState.self) private var state
    @Environment(Progress.self) private var progress
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Leonida.styleKey) private var original = false
    @State private var item: PhotosPickerItem?
    @State private var showPro = false

    var body: some View {
        @Bindable var state = state
        List {
            Group {
                Section {
                    Picker("Map style", selection: $original) {
                        Text("Hologram").tag(false)
                        Text("Original colors").tag(true)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Map style")
                }
                Section("Layers") {
                    ForEach(VFPlaceKind.allCases.filter { $0 != .region }) { k in
                        Toggle(isOn: Binding(get: { state.layers.contains(k) }, set: { on in if on { state.layers.insert(k) } else { state.layers.remove(k) } })) {
                            HStack {
                                Label { Text(k.title) } icon: { Image(systemName: k.icon).foregroundStyle(MapColors.color(k)) }
                                if k.pro && !store.isPro { Spacer(); Text("Pro").font(.caption.bold()).foregroundStyle(VF.sunset) }
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
            .vfRows()
            .tint(VF.flamingo)
        }
        .navigationTitle("Map")
        .navigationBarTitleDisplayMode(.inline)
        .vfScreen()
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
                item = nil
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
        let color = VFPin.colors[abs(pin.color) % VFPin.colors.count]
        Form {
            Group {
                Section {
                    TextField("Name", text: $pin.name)
                    TextField("Note", text: $pin.note, axis: .vertical).lineLimit(2...6)
                }
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(VFPin.icons, id: \.self) { i in
                            Button { pin.icon = i } label: {
                                Image(systemName: i).frame(width: 40, height: 40)
                                    .foregroundStyle(pin.icon == i ? VF.ink : VF.text)
                                    .background(pin.icon == i ? color : Color.white.opacity(0.06), in: .circle)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(verbatim: i))
                            .accessibilityAddTraits(pin.icon == i ? .isSelected : [])
                        }
                    }
                }
                Section("Color") {
                    HStack {
                        ForEach(VFPin.colors.indices, id: \.self) { c in
                            Button { pin.color = c } label: {
                                Circle().fill(VFPin.colors[c]).frame(width: 30, height: 30)
                                    .overlay(Circle().stroke(.white, lineWidth: pin.color == c ? 2 : 0).padding(-3))
                                    .shadow(color: VFPin.colors[c].opacity(pin.color == c ? 0.8 : 0), radius: 6)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(verbatim: "\(c + 1)"))
                            .accessibilityAddTraits(pin.color == c ? .isSelected : [])
                        }
                    }
                }
                Section {
                    Button("Delete pin", role: .destructive) { progress.remove(pin); dismiss() }
                }
            }
            .vfRows()
        }
        .navigationTitle("Pin")
        .navigationBarTitleDisplayMode(.inline)
        .vfScreen()
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
                .foregroundStyle(VF.text.opacity(0.9))
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(VF.ink.opacity(0.82), in: .capsule)
                .overlay(Capsule().stroke(VF.hairline, lineWidth: 1))
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
            Group {
                Section {
                    Text("The map is the GTA VI Community Map v18, drawn by Yanis and the GTA mapping community, from the tiles of GTADB.org. Places come from the GTADB.org landmarks. Both are shared under the Creative Commons Attribution 4.0 license. We cropped the map to Leonida and grouped the places into layers.")
                    Text("The hologram style only recolors the same map on your screen. You can switch back to its original colors in the map's layers.").foregroundStyle(VF.textDim)
                    Text("It's a fan map, not Rockstar's, and it keeps improving.").foregroundStyle(VF.textDim)
                }
                Section {
                    Link("map.gtadb.org", destination: Leonida.sourceURL)
                    Link("Creative Commons Attribution 4.0", destination: Leonida.licenseURL)
                }
            }
            .vfRows()
        }
        .navigationTitle("Map credits")
        .navigationBarTitleDisplayMode(.inline)
        .vfScreen()
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
                        FilterChip(kind: k, on: on) {
                            withAnimation(.snappy) { state.layers = on ? VFPlaceKind.defaultLayers : [k] }
                        }
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

/// Un filtre : en verre au repos (l'icône à la couleur de la catégorie), plein et lumineux quand il est choisi
/// (texte sombre sur la couleur, pour rester lisible).
private struct FilterChip: View {
    var kind: VFPlaceKind
    var on: Bool
    var action: () -> Void

    var body: some View {
        let color = MapColors.color(kind)
        let button = Button(action: action) {
            Label { Text(kind.title) } icon: { Image(systemName: kind.icon).foregroundStyle(on ? VF.ink : color) }
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .foregroundStyle(on ? VF.ink : VF.text)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        if on {
            button.background(color, in: Capsule()).shadow(color: color.opacity(0.7), radius: 8)
        } else {
            button.vfGlass(in: Capsule(), interactive: true)
        }
    }
}
