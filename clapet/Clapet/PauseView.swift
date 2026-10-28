import SwiftUI

/// Demande d'afficher la pause (posée par l'action Raccourcis « Faire une pause à l'ouverture »).
@Observable
final class PauseCenter {
    static let shared = PauseCenter()
    var pending = false
}

/// La pause à l'ouverture : quelques secondes pour respirer, puis on continue ou on referme.
/// Refermer dans la foulée compte une « ouverture évitée ».
struct PauseView: View {
    @Environment(ClapetModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var breathe = false
    @State private var ready = false
    @State private var declined = false
    @State private var startToday = 0

    private let mint = Color(red: 0.36, green: 0.89, blue: 0.78)

    var body: some View {
        let s = model.stats
        let day = s.day()
        ZStack {
            Color(red: 0.04, green: 0.07, blue: 0.07).ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(mint.opacity(0.12))
                    Circle()
                        .stroke(mint.opacity(0.55), lineWidth: 2)
                    Group {
                        if declined {
                            Text("Fold it 🙂")
                        } else if ready {
                            Text("Your call")
                        } else {
                            Text("Breathe")
                        }
                    }
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                }
                .frame(width: 220, height: 220)
                .scaleEffect(breathe ? 1.0 : 0.6)
                .padding(.bottom, 8)

                if declined {
                    Text("Close your phone now: it counts as an unfold resisted.")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.85))
                } else {
                    Text("Unfold #\(day.opens) today")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("\(s.today) folds · limit \(s.goal)")
                        .font(.headline)
                        .foregroundStyle(s.today > s.goal ? Color(red: 1, green: 0.45, blue: 0.42) : mint)
                    if let last = s.lastClose {
                        Text("Last fold \(last, format: .relative(presentation: .named))")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                Spacer()
                if ready && !declined {
                    VStack(spacing: 12) {
                        Button { declined = true } label: {
                            Text("Not now, I'll close it")
                                .font(.headline)
                                .frame(maxWidth: 360)
                                .padding(.vertical, 15)
                                .background(Capsule().fill(mint))
                                .foregroundStyle(.black)
                        }
                        Button { dismiss() } label: {
                            Text("I need my phone")
                                .font(.headline)
                                .frame(maxWidth: 360)
                                .padding(.vertical, 15)
                                .background(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                                .foregroundStyle(.white)
                        }
                    }
                    .transition(.opacity)
                }
                if declined {
                    Button { dismiss() } label: {
                        Text("Back")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                if day.resisted > 0 {
                    Text("\(day.resisted) unfolds resisted today")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(mint)
                }
            }
            .padding(28)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            startToday = model.stats.today
            withAnimation(.easeInOut(duration: 3)) { breathe = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeOut(duration: 0.3)) { ready = true }
            }
        }
        .onChange(of: model.stats.today) { _, now in
            // Refermé après « Pas maintenant » : une ouverture évitée.
            guard declined, now > startToday else { return }
            model.recordResisted()
            dismiss()
        }
    }
}
