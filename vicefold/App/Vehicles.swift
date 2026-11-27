// Vehicles.swift — Vicefold
//
// Les véhicules de Leonida : nom, constructeur, catégorie, et le prix dès qu'il est connu. La liste vient du projet
// libre gta6-data (licence MIT), relevée sur gta6intel.com, et se met à jour toute seule (Content/vehicles.json,
// synchronisé chaque jour par vicefold/tools/vehicles.py). Seuls des faits sont repris, et les sources sont créditées.

import SwiftUI

struct VFVehicle: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var maker: String?
    var kind: String
    var price: Int?
}

struct VFVehicleList: Codable {
    var version: Int
    var updated: String
    var credit: String
    var vehicles: [VFVehicle]
    static let empty = VFVehicleList(version: 0, updated: "", credit: "", vehicles: [])
}

/// Les catégories, dans l'ordre d'affichage.
enum VehicleKind: String, CaseIterable, Identifiable {
    case superCar = "super", sports, classic, muscle, coupe, sedan, compact, suv, offroad, pickup, van, motorcycle, cycle
    case boat, plane, helicopter, emergency, service, utility, commercial, industrial, military, other
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .superCar: return "Super"
        case .sports: return "Sports"
        case .classic: return "Sports classics"
        case .muscle: return "Muscle"
        case .coupe: return "Coupes"
        case .sedan: return "Sedans"
        case .compact: return "Compacts"
        case .suv: return "SUVs"
        case .offroad: return "Off-road"
        case .pickup: return "Pickups"
        case .van: return "Vans"
        case .motorcycle: return "Motorcycles"
        case .cycle: return "Bicycles"
        case .boat: return "Boats"
        case .plane: return "Planes"
        case .helicopter: return "Helicopters"
        case .emergency: return "Emergency"
        case .service: return "Service"
        case .utility: return "Utility"
        case .commercial: return "Commercial"
        case .industrial: return "Industrial"
        case .military: return "Military"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .superCar, .sports, .classic, .coupe: return "car.side.fill"
        case .muscle, .sedan, .compact: return "car.fill"
        case .suv, .offroad, .pickup: return "suv.side.fill"
        case .van, .commercial, .utility, .service: return "box.truck.fill"
        case .industrial: return "truck.box.fill"
        case .motorcycle: return "motorcycle"
        case .cycle: return "bicycle"
        case .boat: return "sailboat.fill"
        case .plane: return "airplane"
        case .helicopter: return "fanblades.fill"
        case .emergency: return "light.beacon.max.fill"
        case .military: return "shield.lefthalf.filled"
        case .other: return "questionmark.circle"
        }
    }
}

/// La liste en cours : celle livrée avec l'app, ou une plus récente téléchargée (même serveur que le guide).
@MainActor @Observable
final class VehicleStore {
    static let shared = VehicleStore()
    private(set) var list: VFVehicleList = .empty
    private var refreshed = false

    private var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("vehicles.json")
    }

    init() {
        let bundled = Bundle.main.url(forResource: "vehicles", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(VFVehicleList.self, from: $0) }
        let cached = (try? Data(contentsOf: cacheURL)).flatMap { try? JSONDecoder().decode(VFVehicleList.self, from: $0) }
        if let cached, cached.version >= (bundled?.version ?? 0) { list = cached } else if let bundled { list = bundled }
    }

    func refresh() async {
        guard !refreshed, ShotMode.route == nil else { return }
        refreshed = true
        var req = URLRequest(url: ContentStore.remoteBase.appendingPathComponent("vehicles.json"))
        req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let l = try? JSONDecoder().decode(VFVehicleList.self, from: data),
              l.version > list.version else { return }
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheURL)
        list = l
    }
}

struct VehiclesView: View {
    /// Une recherche déjà remplie (quand on arrive de la recherche générale).
    var initialQuery = ""
    @State private var store = VehicleStore.shared
    @State private var query = ""
    @State private var kind: VehicleKind?

    /// Une catégorie inconnue de cette version de l'app (la liste se met à jour toute seule) se range dans « Autres ».
    private func kindOf(_ v: VFVehicle) -> VehicleKind { VehicleKind(rawValue: v.kind) ?? .other }

    private var filtered: [VFVehicle] {
        store.list.vehicles.filter { v in
            (kind == nil || kindOf(v) == kind) &&
            (query.isEmpty || v.name.localizedCaseInsensitiveContains(query) || (v.maker ?? "").localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        let list = filtered
        let byKind = Dictionary(grouping: list, by: kindOf)
        let counts = Dictionary(grouping: store.list.vehicles, by: kindOf).mapValues(\.count)
        List {
            Group {
                if !store.list.vehicles.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                chip(nil, title: "All", count: store.list.vehicles.count)
                                ForEach(VehicleKind.allCases.filter { counts[$0] != nil }) { k in
                                    chip(k, title: k.title, count: counts[k] ?? 0)
                                }
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 8)
                        }
                        .scrollClipDisabled()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }
                ForEach(VehicleKind.allCases.filter { byKind[$0] != nil }) { k in
                    Section {
                        ForEach(byKind[k] ?? []) { v in row(v) }
                    } header: {
                        Label(k.title, systemImage: k.icon)
                    }
                }
                if store.list.vehicles.isEmpty {
                    Section { VFEmptyState(icon: "car.side", title: "No vehicles yet", message: "They arrive with a content update, no app update needed.").listRowBackground(Color.clear) }
                } else if list.isEmpty {
                    Section { ContentUnavailableView.search(text: query).listRowBackground(Color.clear) }
                }
                Section {
                    Text("Prices appear here as soon as they're known. Vehicle list: gta6-data (MIT license), from gta6intel.com. Updated \(store.list.updated).")
                        .font(.footnote)
                        .foregroundStyle(VF.textDim)
                }
            }
            .vfRows()
        }
        .searchable(text: $query)
        .navigationTitle("Vehicles")
        .vfScreen()
        .onAppear { if query.isEmpty { query = initialQuery } }
        .task { await store.refresh() }
    }

    private func chip(_ k: VehicleKind?, title: LocalizedStringKey, count: Int) -> some View {
        let on = kind == k
        return Button {
            withAnimation(VFMotion.snap) { kind = k }
        } label: {
            HStack(spacing: 5) {
                if let k { Image(systemName: k.icon).font(.caption) }
                Text(title)
                Text(verbatim: "\(count)").font(VF.mono(10)).opacity(0.75)
            }
            .vfChip(selected: on, color: VF.palm)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func row(_ v: VFVehicle) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(v.name).font(.headline).foregroundStyle(VF.text)
                if let m = v.maker { Text(m).font(.subheadline).foregroundStyle(VF.textDim) }
            }
            Spacer()
            if let p = v.price {
                Text(p, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(VF.mono(13, weight: .bold))
                    .foregroundStyle(VF.palm)
                    .shadow(color: VF.palm.opacity(0.5), radius: 4)
            } else {
                Text("Price not known yet").font(.caption).foregroundStyle(VF.textFaint)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
