// AdventView.swift — Allô Père Noël
//
// Vingt-quatre messages du Père Noël. En décembre, une porte s'ouvre chaque jour.
// Le reste de l'année, le Pass les ouvre toutes (pour que l'achat serve aussi en novembre).
// Sans le Pass, seule la première porte s'écoute : c'est l'aperçu.

import SwiftUI

struct AdventView: View {
    @Environment(AppModel.self) private var model
    @Environment(MagicStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var lines: [String] = []

    private var decemberDay: Int? {
        let c = Calendar.current.dateComponents([.month, .day], from: Date())
        guard c.month == 12, let day = c.day, (1...24).contains(day) else { return nil }
        return day
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("A message from Santa, each day of December.")
                        .font(.ui(16))
                        .foregroundStyle(Noel.cream.opacity(0.78))
                    if decemberDay == nil {
                        Text("Before December, the Pass opens every door.")
                            .font(.ui(14))
                            .foregroundStyle(Noel.goldLight.opacity(0.9))
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                        ForEach(1...24, id: \.self) { day in
                            door(day)
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(red: 0.05, green: 0.08, blue: 0.15).ignoresSafeArea())
            .navigationTitle(Text("Advent calendar"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task { lines = Self.load() }
    }

    @ViewBuilder private func door(_ day: Int) -> some View {
        let open = isOpen(day)
        Button {
            if open {
                let line = lines.indices.contains(day - 1) ? lines[day - 1] : lines.first ?? ""
                guard !line.isEmpty else { return }
                Task { await model.call.speakLine(line) }
            } else if !store.owned {
                model.sheet = .paywall
            }
        } label: {
            VStack(spacing: 4) {
                Text("\(day)")
                    .font(.tale(22))
                if !open {
                    Image(systemName: store.owned ? "clock" : "lock.fill")
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .foregroundStyle(open ? Noel.night : Noel.cream)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(open ? AnyShapeStyle(Noel.goldGradient) : AnyShapeStyle(Noel.night.opacity(0.7))))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Noel.gold.opacity(open ? 0 : 0.35), lineWidth: 1))
        }
        .disabled(model.call.previewing || (!open && store.owned))
        .accessibilityLabel(Text("Day \(day)"))
    }

    /// Décembre : les jours passés et le jour même. Sinon : la porte 1 sans Pass, toutes les portes avec.
    private func isOpen(_ day: Int) -> Bool {
        if let today = decemberDay {
            if store.owned { return day <= today }
            return day == 1 && day <= today
        }
        return store.owned || day == 1
    }

    private static func load() -> [String] {
        let lang = String((Bundle.main.preferredLocalizations.first ?? "en").prefix(2))
        guard let url = Bundle.main.url(forResource: "messages", withExtension: "json", subdirectory: "Advent")
                ?? Bundle.main.url(forResource: "messages", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let all = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [] }
        return all[lang] ?? all["en"] ?? []
    }
}
