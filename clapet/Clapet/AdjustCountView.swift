import SwiftUI
import UniformTypeIdentifiers

/// Corriger le compteur à la main : taper directement les plis d'aujourd'hui, ou le total depuis le début.
struct AdjustCountView: View {
    @Environment(ClapetModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    // Des textes plutôt que des nombres : la valeur tapée est prise même sans touche « Retour ».
    @State private var todayText = ""
    @State private var totalText = ""
    @State private var startToday = 0
    @State private var startTotal = 0
    @State private var totalEdited = false
    @State private var opensText = ""
    @State private var startOpens = 0
    @State private var opensEdited = false
    // Une journée passée (stats d'avant Foldly, ou une journée à corriger)
    @State private var pastDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    @State private var pastClosesText = ""
    @State private var pastOpensText = ""
    @State private var pastStart = (closes: 0, opens: 0)
    @State private var pastEdited = false
    @State private var added: String?
    @State private var picking = false
    @State private var found: HistoryImport?
    @State private var importNote: String?
    @State private var loaded = false
    @FocusState private var focus: Field?

    private enum Field { case today, total, opens, pastCloses, pastOpens }

    private var today: Int { Self.number(todayText) }
    private var total: Int { Self.number(totalText) }

    private static func number(_ text: String) -> Int {
        Int(String(text.filter { ("0"..."9").contains($0) }.prefix(8))) ?? 0
    }

    /// Le total tant qu'on ne l'a pas touché : il suit la correction d'aujourd'hui.
    private var followingTotal: Int { max(today, startTotal + (today - startToday) + pastDelta.closes) }
    private var followingOpens: Int { max(0, startOpens + pastDelta.opens) }
    private var pastDelta: (closes: Int, opens: Int) {
        pastEdited ? (Self.number(pastClosesText) - pastStart.closes, Self.number(pastOpensText) - pastStart.opens) : (0, 0)
    }
    private var yesterday: Date { Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date() }

    private func loadPast() {
        let d = model.stats.day(pastDate)
        pastStart = (d.closes, d.opens)
        pastClosesText = String(d.closes)
        pastOpensText = String(d.opens)
        pastEdited = false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    numberRow(text: $todayText, range: 0...100_000, field: .today)
                } header: {
                    Text("Today")
                } footer: {
                    Text("Type the number you want, or use − and +. The lifetime total follows the same change.")
                }

                Section {
                    LabeledContent { numberRow(text: $totalText, range: 0...10_000_000, field: .total) } label: { Text("Folds") }
                    LabeledContent { numberRow(text: $opensText, range: 0...10_000_000, field: .opens) } label: { Text("Unfolds") }
                } header: {
                    Text("All time")
                } footer: {
                    Text("Useful if you were counting before Foldly. It can't be lower than today's folds.")
                }

                Section {
                    Button { picking = true } label: {
                        Label { Text("Import a file") } icon: { Image(systemName: "square.and.arrow.down") }
                    }
                    if let found {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(found.days.count) days found, \(found.totalCloses) folds")
                                .font(.subheadline.weight(.semibold))
                            if let a = found.first.flatMap(ClapetStats.date), let b = found.last.flatMap(ClapetStats.date) {
                                Text("From \(a.formatted(date: .abbreviated, time: .omitted)) to \(b.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            let overlap = model.stats.importOverlap(found)
                            if overlap > 0 {
                                Text("\(overlap) days already counted by Foldly keep the higher of the two counts.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        Button { runImport(found) } label: {
                            Label { Text("Add these days") } icon: { Image(systemName: "checkmark.circle.fill") }
                        }
                    }
                    if let importNote {
                        Text(importNote).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Import your history")
                } footer: {
                    Text("A CSV, text or JSON file from Scriptable, a shortcut or another app: one line per day (date, folds, unfolds) or one line per fold (its date and time). Days already counted by Foldly are never counted twice.")
                }

                Section {
                    DatePicker(selection: $pastDate, in: ...yesterday, displayedComponents: .date) { Text("Day") }
                    LabeledContent { numberRow(text: $pastClosesText, range: 0...100_000, field: .pastCloses) } label: { Text("Folds") }
                    LabeledContent { numberRow(text: $pastOpensText, range: 0...100_000, field: .pastOpens) } label: { Text("Unfolds") }
                    Button { addPastDay() } label: {
                        Label { Text("Add this day") } icon: { Image(systemName: "plus.circle.fill") }
                    }
                    .disabled(!pastEdited)
                    if let added {
                        Text(added).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("A past day")
                } footer: {
                    Text("Add the days you tracked before Foldly (with Scriptable or another app): they show up in your history, records and totals. After each day, the day before comes up.")
                }
            }
            .navigationTitle(Text("Adjust the count"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        Text("Save").fontWeight(.semibold)
                    }
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                startToday = model.stats.today
                startTotal = model.stats.totalCloses
                startOpens = model.stats.totalOpens
                opensText = String(startOpens)
                loadPast()
                todayText = String(startToday)
                totalText = String(startTotal)
                focus = .today
            }
            .onChange(of: todayText) { _, _ in
                if !totalEdited { totalText = String(followingTotal) }
            }
            .onChange(of: totalText) { _, _ in
                if total != followingTotal { totalEdited = true }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .json, .text, .data]) { result in
                readFile(result)
            }
            .onChange(of: opensText) { _, _ in
                if Self.number(opensText) != followingOpens { opensEdited = true }
            }
            .onChange(of: pastDate) { _, _ in
                loadPast()
                if !totalEdited { totalText = String(followingTotal) }
                if !opensEdited { opensText = String(followingOpens) }
            }
            .onChange(of: pastClosesText) { _, _ in pastChanged() }
            .onChange(of: pastOpensText) { _, _ in pastChanged() }
        }
        .tint(.dfAccent)
    }

    private func numberRow(text: Binding<String>, range: ClosedRange<Int>, field: Field) -> some View {
        let value = Binding<Int>(
            get: { Self.number(text.wrappedValue) },
            set: { text.wrappedValue = String($0) }
        )
        return HStack(spacing: 12) {
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .focused($focus, equals: field)
            Stepper(value: value, in: range) { EmptyView() }
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }

    private func pastChanged() {
        pastEdited = Self.number(pastClosesText) != pastStart.closes || Self.number(pastOpensText) != pastStart.opens
        if !totalEdited { totalText = String(followingTotal) }
        if !opensEdited { opensText = String(followingOpens) }
    }

    /// Enregistre la journée tout de suite, puis passe à la veille (pour en ajouter plusieurs à la suite).
    private func addPastDay() {
        let date = pastDate
        model.adjust(today: nil, total: nil, past: (date, Self.number(pastClosesText), Self.number(pastOpensText)))
        added = String(localized: "\(date.formatted(date: .abbreviated, time: .omitted)) added.")
        if !totalEdited { startTotal = model.stats.totalCloses }
        if !opensEdited { startOpens = model.stats.totalOpens }
        pastDate = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        loadPast()
        if !totalEdited { totalText = String(followingTotal) }
        if !opensEdited { opensText = String(followingOpens) }
    }

    private func readFile(_ result: Result<URL, Error>) {
        found = nil
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? String(data: data, encoding: .isoLatin1) else {
            importNote = String(localized: "This file can't be read.")
            return
        }
        let r = HistoryImport.parse(text)
        if r.isEmpty {
            importNote = String(localized: "No dates found in this file. Its format isn't supported yet.")
        } else {
            importNote = nil
            found = r
        }
    }

    private func runImport(_ r: HistoryImport) {
        let n = model.importHistory(r)
        found = nil
        importNote = String(localized: "\(n) days added to your history.")
        startTotal = model.stats.totalCloses
        startOpens = model.stats.totalOpens
        if !totalEdited { totalText = String(followingTotal) }
        if !opensEdited { opensText = String(followingOpens) }
        loadPast()
    }

    private func save() {
        let newToday = max(0, today)
        model.adjust(today: newToday != startToday ? newToday : nil,
                     total: totalEdited ? max(newToday, total) : nil,
                     totalOpens: opensEdited ? Self.number(opensText) : nil,
                     past: pastEdited ? (pastDate, Self.number(pastClosesText), Self.number(pastOpensText)) : nil)
        dismiss()
    }
}
