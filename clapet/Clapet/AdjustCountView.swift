import SwiftUI

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
    @State private var loaded = false
    @FocusState private var focus: Field?

    private enum Field { case today, total }

    private var today: Int { Self.number(todayText) }
    private var total: Int { Self.number(totalText) }

    private static func number(_ text: String) -> Int {
        Int(String(text.filter { ("0"..."9").contains($0) }.prefix(8))) ?? 0
    }

    /// Le total tant qu'on ne l'a pas touché : il suit la correction d'aujourd'hui.
    private var followingTotal: Int { max(today, startTotal + (today - startToday)) }

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
                    numberRow(text: $totalText, range: 0...10_000_000, field: .total)
                } header: {
                    Text("All time")
                } footer: {
                    Text("Useful if you were counting before Foldly. It can't be lower than today's folds.")
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

    private func save() {
        let newToday = max(0, today)
        model.adjust(today: newToday != startToday ? newToday : nil,
                     total: totalEdited ? max(newToday, total) : nil)
        dismiss()
    }
}
