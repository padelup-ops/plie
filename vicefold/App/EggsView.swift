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
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: "\(found)").font(VF.display(60)).monospacedDigit().foregroundStyle(VF.gradient)
                            .shadow(color: VF.flamingo.opacity(0.55), radius: 12)
                            .contentTransition(.numericText())
                        Text("of \(eggs.count) found").font(VF.display(24, relativeTo: .title2)).foregroundStyle(VF.text)
                    }
                    .accessibilityElement(children: .combine)
                    VFBar(value: Double(found) / Double(max(1, eggs.count)))
                    Text("Secrets spotted by players since launch. Tap one to see where; the how stays hidden until you ask.")
                        .font(.subheadline).foregroundStyle(VF.textDim)
                    Picker("Show", selection: $filter) {
                        Text("All").tag(0)
                        Text("Found").tag(1)
                        Text("To find").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 4)
                }
                if eggs.isEmpty {
                    VFEmptyState(icon: "oval.portrait", title: "No easter eggs yet", message: "They arrive with a content update, no app update needed.")
                } else if shown.isEmpty {
                    VFEmptyState(icon: filter == 1 ? "oval.portrait" : "checkmark.seal.fill",
                                 title: filter == 1 ? "Nothing found yet" : "Everything found",
                                 message: filter == 1 ? "Open a secret and mark it as found when you see it in the game." : nil)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 14)], spacing: 14) {
                    ForEach(shown) { e in
                        NavigationLink { EggDetail(egg: e) } label: { HoloCard(egg: e, photoHeight: 120) }
                            .buttonStyle(.plain)
                    }
                }
                Text("Written by us from what players and the press reported. \"Reported\" means only one source so far.")
                    .font(.caption).foregroundStyle(VF.textDim)

                SectionTitle(title: "My finds", action: "Add my find") { editing = VFMyEgg(title: "") }
                if progress.data.myEggs.isEmpty {
                    Label("Spotted something odd? Keep it here with a photo. It stays on your devices.", systemImage: "camera.viewfinder")
                        .font(.subheadline).foregroundStyle(VF.textDim)
                        .vfCard()
                } else {
                    ForEach(progress.data.myEggs) { e in
                        Button { editing = e } label: {
                            HStack(spacing: 12) {
                                MyEggThumb(egg: e)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.title).font(.headline).foregroundStyle(VF.text).multilineTextAlignment(.leading)
                                    if !e.place.isEmpty { Text(e.place).font(.caption).foregroundStyle(VF.textDim) }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(VF.textFaint)
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

struct EggDetail: View {
    var egg: VFEgg
    @Environment(Progress.self) private var progress
    @State private var showHow = false
    @State private var revealed = false
    @State private var map = MapState()

    var body: some View {
        let hidden = progress.hidden(egg.spoiler) && !revealed
        let found = progress.found(egg)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label(egg.area, systemImage: "mappin.and.ellipse").font(VF.mono(11)).textCase(.uppercase).foregroundStyle(VF.cyan)
                Text(hidden ? String(localized: "Hidden until your chapter") : egg.title).font(VF.display(36)).foregroundStyle(VF.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if egg.confirmed != true {
                    Label("Reported by one source so far", systemImage: "questionmark.circle").font(.caption.weight(.semibold)).foregroundStyle(VF.sun)
                }
                if hidden {
                    SpoilerGate(chapter: egg.spoiler ?? 0) { revealed = true }
                } else {
                    Text(egg.summary).foregroundStyle(VF.text).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    if let how = egg.how {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("How to find it").font(.headline).foregroundStyle(VF.text)
                            if showHow {
                                Text(how).foregroundStyle(VF.text).fixedSize(horizontal: false, vertical: true)
                            } else {
                                Button { withAnimation(VFMotion.ease) { showHow = true } } label: { Label("Show how to find it", systemImage: "eye") }
                                    .buttonStyle(.vf(.secondary, compact: true))
                            }
                        }
                        .vfCard(radius: 18, padding: 16)
                    }
                    if let x = egg.x, let y = egg.y {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Roughly here").font(.headline).foregroundStyle(VF.text)
                            LeonidaMapView(decorated: false)
                                .environment(map)
                                .frame(height: 260)
                                .allowsHitTesting(false)
                                .clipShape(.rect(cornerRadius: 16, style: .continuous))
                                .overlay {
                                    ZStack {
                                        Circle().stroke(VF.flamingo.opacity(0.6), lineWidth: 1.5).frame(width: 54, height: 54)
                                        Image(systemName: "oval.portrait.fill")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundStyle(VF.ink)
                                            .frame(width: 32, height: 32).background(VF.flamingo, in: .circle)
                                            .overlay(Circle().stroke(.white, lineWidth: 2))
                                            .shadow(color: VF.flamingo, radius: 8)
                                    }
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                                }
                                .vfTicks(VF.cyan, length: 10, inset: 7)
                                .onAppear {
                                    map.layers = []
                                    map.showPins = false
                                    map.animateFocus = false
                                    map.zoom = 5
                                    map.focus = CGPoint(x: x * Leonida.size.width, y: y * Leonida.size.height)
                                }
                            Text("The spot is approximate.").font(.caption).foregroundStyle(VF.textDim)
                        }
                        .vfCard(radius: 18, padding: 12)
                    }
                    if let refs = egg.refs, !refs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("A nod to").font(.headline).foregroundStyle(VF.text)
                            ForEach(refs, id: \.self) { r in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Circle().fill(VF.cyan).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                                    Text(r).font(.subheadline).foregroundStyle(VF.textDim)
                                }
                            }
                        }
                        .vfCard(radius: 18, padding: 16)
                    }
                }
                Button { progress.toggle(egg) } label: {
                    Label(found ? "Found" : "Mark as found", systemImage: found ? "checkmark.circle.fill" : "circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.vf(found ? .done : .primary))
                .padding(.top, 4)
            }
            .padding()
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(VFBackdrop())
        .navigationTitle("Easter egg")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Recents.shared.opened(.egg, egg.id) }
    }
}

struct MyEggThumb: View {
    var egg: VFMyEgg
    var body: some View {
        Group {
            if let f = egg.photo, let img = UIImage(contentsOfFile: Progress.eggPhotoURL(f).path) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Image(systemName: "sparkles").foregroundStyle(VF.ink).frame(maxWidth: .infinity, maxHeight: .infinity).background(VF.blaze)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(.rect(cornerRadius: 10, style: .continuous))
    }
}

struct MyEggEditor: View {
    @State var egg: VFMyEgg
    @Environment(Progress.self) private var progress
    @Environment(\.dismiss) private var dismiss
    @State private var item: PhotosPickerItem?

    var body: some View {
        Form {
            Group {
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
            .vfRows()
        }
        .navigationTitle("My find")
        .navigationBarTitleDisplayMode(.inline)
        .vfScreen()
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
