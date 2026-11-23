// EggsView.swift — Vicefold
//
// Le tracker d'easter eggs : les secrets repérés par les joueurs (sans spoiler : le « comment » reste caché tant
// qu'on ne le demande pas), ceux que tu as trouvés, et tes propres trouvailles, avec une photo si tu veux.

import PhotosUI
import SwiftUI

struct EggsView: View {
    @Environment(ContentStore.self) private var content
    @Environment(Progress.self) private var progress
    @State private var editing: VFMyEgg?
    @State private var filter = 0

    var body: some View {
        let eggs = content.content.eggs
        let shown = eggs.filter { filter == 0 || (filter == 1) == progress.found($0) }
        let found = eggs.filter { progress.found($0) }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(found)").font(VF.display(56)).monospacedDigit().foregroundStyle(VF.flamingo)
                        Text("of \(eggs.count) found").font(VF.display(24, relativeTo: .title2))
                    }
                    Text("Secrets spotted by players since launch. Tap one to see where; the how stays hidden until you ask.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Picker("Show", selection: $filter) {
                        Text("All").tag(0)
                        Text("Found").tag(1)
                        Text("To find").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 6)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 22) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, e in
                        NavigationLink { EggDetail(egg: e) } label: {
                            Polaroid(egg: e, photoHeight: 120).rotationEffect(.degrees(i % 3 == 0 ? -1.4 : (i % 3 == 1 ? 1.1 : -0.4)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Written by us from what players and the press reported. \"Reported\" means only one source so far.")
                    .font(.caption).foregroundStyle(.secondary)

                SectionTitle(title: "My finds", action: "Add my find") { editing = VFMyEgg(title: "") }
                if progress.data.myEggs.isEmpty {
                    Text("Spotted something odd? Keep it here with a photo. It stays on your devices.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .vfCard()
                } else {
                    ForEach(progress.data.myEggs) { e in
                        Button { editing = e } label: {
                            HStack(spacing: 12) {
                                MyEggThumb(egg: e)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.title).font(.headline).foregroundStyle(.primary)
                                    if !e.place.isEmpty { Text(e.place).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .vfCard(radius: 18, padding: 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(VFBackdrop())
        .navigationTitle("Easter eggs")
        .sheet(item: $editing) { e in NavigationStack { MyEggEditor(egg: e) } }
    }
}

struct EggRow: View {
    var egg: VFEgg
    @Environment(Progress.self) private var progress

    var body: some View {
        let hidden = progress.hidden(egg.spoiler)
        HStack(spacing: 12) {
            Button { progress.toggle(egg) } label: {
                Image(systemName: progress.found(egg) ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(progress.found(egg) ? VF.teal : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(progress.found(egg) ? "Found" : "Not found yet")
            VStack(alignment: .leading, spacing: 3) {
                Text(hidden ? String(localized: "Hidden until your chapter") : egg.title).font(.headline)
                HStack(spacing: 6) {
                    Text(egg.area)
                    if egg.confirmed != true {
                        Text("Reported").font(.caption2.bold()).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.orange.opacity(0.2), in: .capsule).foregroundStyle(.orange)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct EggDetail: View {
    var egg: VFEgg
    @Environment(Progress.self) private var progress
    @State private var showHow = false
    @State private var map = MapState()

    var body: some View {
        let hidden = progress.hidden(egg.spoiler)
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(hidden ? String(localized: "Hidden until your chapter") : egg.title).font(.title2.bold())
                    Label(egg.area, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(.secondary)
                    if !hidden { Text(egg.summary).fixedSize(horizontal: false, vertical: true) }
                    if egg.confirmed != true {
                        Label("Reported by one source so far", systemImage: "questionmark.circle").font(.caption).foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 4)
                Button { progress.toggle(egg) } label: {
                    Label(progress.found(egg) ? "Found" : "Mark as found", systemImage: progress.found(egg) ? "checkmark.circle.fill" : "circle")
                }
                .tint(progress.found(egg) ? VF.teal : VF.coral)
            }
            if !hidden, let how = egg.how {
                Section {
                    if showHow {
                        Text(how).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Button { withAnimation { showHow = true } } label: { Label("Show how to find it", systemImage: "eye") }
                    }
                } header: {
                    Text("How to find it")
                }
            }
            if let x = egg.x, let y = egg.y {
                Section {
                    LeonidaMapView()
                        .environment(map)
                        .frame(height: 280)
                        .allowsHitTesting(false)
                        .listRowInsets(EdgeInsets())
                        .onAppear {
                            map.layers = []
                            map.showPins = false
                            map.animateFocus = false
                            map.zoom = 5
                            map.focus = CGPoint(x: x * Leonida.size.width, y: y * Leonida.size.height)
                        }
                        .overlay {
                            Image(systemName: "oval.portrait.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.white, VF.magenta)
                                .padding(8).background(VF.magenta, in: .circle)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                                .allowsHitTesting(false)
                        }
                } header: {
                    Text("Roughly here")
                } footer: {
                    Text("The spot is approximate.")
                }
            }
            if let refs = egg.refs, !refs.isEmpty, !hidden {
                Section("A nod to") {
                    ForEach(refs, id: \.self) { Text($0) }
                }
            }
        }
        .navigationTitle("Easter egg")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MyEggThumb: View {
    var egg: VFMyEgg
    var body: some View {
        Group {
            if let f = egg.photo, let img = UIImage(contentsOfFile: Progress.eggPhotoURL(f).path) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Image(systemName: "sparkles").foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity).background(VF.gradient)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(.rect(cornerRadius: 10))
    }
}

struct MyEggEditor: View {
    @State var egg: VFMyEgg
    @Environment(Progress.self) private var progress
    @Environment(\.dismiss) private var dismiss
    @State private var item: PhotosPickerItem?

    var body: some View {
        Form {
            Section {
                TextField("What did you find?", text: $egg.title)
                TextField("Where (area, street, landmark)", text: $egg.place)
                TextField("Note", text: $egg.note, axis: .vertical).lineLimit(2...6)
            }
            Section {
                PhotosPicker(selection: $item, matching: .images) {
                    HStack {
                        MyEggThumb(egg: egg)
                        Text(egg.photo == nil ? "Add a photo" : "Change the photo")
                    }
                }
            }
            if progress.data.myEggs.contains(where: { $0.id == egg.id }) {
                Section { Button("Delete", role: .destructive) { progress.remove(egg); dismiss() } }
            }
        }
        .navigationTitle("My find")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { progress.save(egg); dismiss() }
                    .disabled(egg.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onChange(of: item) { _, it in
            guard let it else { return }
            Task {
                if let data = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: data),
                   let jpg = img.preparingThumbnail(of: CGSize(width: 1600, height: 1600 * img.size.height / max(1, img.size.width)))?.jpegData(compressionQuality: 0.8) {
                    let name = "egg-\(egg.id).jpg"
                    try? jpg.write(to: Progress.eggPhotoURL(name), options: .atomic)
                    egg.photo = name
                }
            }
        }
    }
}
