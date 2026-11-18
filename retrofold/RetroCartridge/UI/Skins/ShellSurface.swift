//
// ShellSurface.swift
// RetroCartridge
//
// The molded body of a console in a skin, with its finish: grainy matte
// plastic, glossy plastic with a pulsing neon edge, translucent plastic
// showing the circuit board inside, or wood-grain laminate. Used by the
// full-size console and by the skin previews.
//

import SwiftUI

struct ShellSurface: View {
    let theme: SkinTheme

    /// Corner radius of the shell outline; nil follows the display's own
    /// corners (`ConcentricRectangle`), for the full-screen console.
    var cornerRadius: CGFloat? = nil

    /// Size of textures and details, 1 on a full display. Miniature
    /// previews pass their own scale so they show the same pattern.
    var detailScale: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var neonPulse = false

    var body: some View {
        ZStack {
            Color.black

            // With Reduce Transparency, clear plastic is drawn solid
            if theme.finish == .translucent && !reduceTransparency {
                CircuitBoard(detailScale: detailScale)
            }

            plastic

            // Molded light falling from the top-leading corner
            LinearGradient(
                colors: [.white.opacity(0.14), .clear, .black.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            switch theme.finish {
            case .glossy:
                specularBand
            case .translucent:
                // Light caught inside the clear plastic
                LinearGradient(
                    colors: [.white.opacity(0.12), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            case .matte, .woodGrain:
                EmptyView()
            }
        }
        .overlay {
            if theme.finish == .glossy {
                neonEdge
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Layers

    @ViewBuilder
    private var plastic: some View {
        switch theme.finish {
        case .matte:
            Rectangle()
                .fill(theme.bodyColor)
                .colorEffect(ShaderLibrary.shellGrain(.float(0.035)))
        case .woodGrain:
            Rectangle()
                .fill(theme.bodyColor)
                .colorEffect(ShaderLibrary.woodGrain(.float(Float(detailScale))))
        case .glossy, .translucent:
            Rectangle()
                .fill(theme.bodyColor)
        }
    }

    /// A narrow diagonal reflection across polished plastic.
    private var specularBand: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.3),
                .init(color: .white.opacity(0.1), location: 0.36),
                .init(color: .clear, location: 0.46),
                .init(color: .clear, location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// A neon tube around the shell's edge in the accent color. It breathes
    /// slowly unless Reduce Motion is on.
    private var neonEdge: some View {
        let lineScale = max(detailScale, 0.4)

        return ZStack {
            edgeShape
                .stroke(theme.accentColor, lineWidth: 6 * lineScale)
                .blur(radius: 10 * lineScale)
            edgeShape
                .stroke(theme.accentColor.opacity(0.9), lineWidth: 2 * lineScale)
        }
        .opacity(reduceMotion ? 0.8 : (neonPulse ? 1 : 0.55))
        .animation(reduceMotion ? nil : Animation.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: neonPulse)
        .onAppear { neonPulse = true }
    }

    private var edgeShape: AnyShape {
        if let cornerRadius {
            return AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        return AnyShape(ConcentricRectangle())
    }
}

// MARK: - Circuit board

/// The circuit board seen through a translucent shell: traces with solder
/// pads, chips and screw posts, laid out the same way on every launch.
struct CircuitBoard: View {
    var detailScale: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            Self.draw(in: &context, size: size, scale: max(detailScale, 0.15))
        }
        .accessibilityHidden(true)
    }

    private static let board = Color(hex: "#0C3326")
    private static let trace = Color(hex: "#2E8B63").opacity(0.75)
    private static let solder = Color(hex: "#C9A34E")

    /// Directions a trace may run in: straight or at 45°.
    private static let directions: [CGVector] = [
        CGVector(dx: 1, dy: 0), CGVector(dx: -1, dy: 0),
        CGVector(dx: 0, dy: 1), CGVector(dx: 0, dy: -1),
        CGVector(dx: 0.7071, dy: 0.7071), CGVector(dx: -0.7071, dy: 0.7071),
        CGVector(dx: 0.7071, dy: -0.7071), CGVector(dx: -0.7071, dy: -0.7071)
    ]

    private static func draw(in context: inout GraphicsContext, size: CGSize, scale: CGFloat) {
        var random = SeededRandom(seed: 0x5EED_CAFE)
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(board))

        let pitch = 18 * scale
        let lineWidth = max(0.5, 1.6 * scale)
        let padSize = 5 * scale

        // Traces, each ending in a solder pad
        let traceCount = min(220, max(12, Int(size.width * size.height / (pitch * pitch * 6))))
        for _ in 0..<traceCount {
            var point = CGPoint(
                x: (random.next() * size.width / pitch).rounded() * pitch,
                y: (random.next() * size.height / pitch).rounded() * pitch
            )
            var path = Path()
            path.move(to: point)
            for _ in 0..<(2 + Int(random.next() * 3)) {
                let direction = directions[Int(random.next() * CGFloat(directions.count)) % directions.count]
                let length = CGFloat(1 + Int(random.next() * 5)) * pitch
                point = CGPoint(x: point.x + direction.dx * length, y: point.y + direction.dy * length)
                path.addLine(to: point)
            }
            context.stroke(path, with: .color(trace), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            let pad = CGRect(x: point.x - padSize / 2, y: point.y - padSize / 2, width: padSize, height: padSize)
            context.fill(Path(ellipseIn: pad), with: .color(solder))
        }

        // Chips with pins along their long edges
        let chipCount = max(2, Int(size.width * size.height / (160_000 * scale * scale)))
        for _ in 0..<min(chipCount, 10) {
            let chip = CGRect(
                x: random.next() * max(1, size.width - 90 * scale),
                y: random.next() * max(1, size.height - 60 * scale),
                width: (40 + random.next() * 50) * scale,
                height: (24 + random.next() * 30) * scale
            )
            let pinSpacing = 6 * scale
            var x = chip.minX + pinSpacing
            while x < chip.maxX - pinSpacing / 2 {
                for y in [chip.minY - 3 * scale, chip.maxY] {
                    context.fill(Path(CGRect(x: x - scale, y: y, width: 2 * scale, height: 3 * scale)), with: .color(solder.opacity(0.8)))
                }
                x += pinSpacing
            }
            context.fill(Path(roundedRect: chip, cornerRadius: 3 * scale), with: .color(Color(white: 0.07)))
            let marker = CGRect(x: chip.minX + 4 * scale, y: chip.minY + 4 * scale, width: 4 * scale, height: 4 * scale)
            context.fill(Path(ellipseIn: marker), with: .color(Color(white: 0.2)))
        }

        // Screw posts near the corners and the middle of the long edges
        let radius = 9 * scale
        let posts: [CGPoint] = [
            CGPoint(x: 0.07, y: 0.05), CGPoint(x: 0.93, y: 0.05),
            CGPoint(x: 0.07, y: 0.95), CGPoint(x: 0.93, y: 0.95),
            CGPoint(x: 0.04, y: 0.5), CGPoint(x: 0.96, y: 0.5)
        ]
        for post in posts {
            let center = CGPoint(x: post.x * size.width, y: post.y * size.height)
            let head = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: head), with: .color(Color(white: 0.1)))
            context.stroke(Path(ellipseIn: head), with: .color(Color(white: 0.3)), lineWidth: max(0.5, scale))
            var slot = Path()
            slot.move(to: CGPoint(x: center.x - radius * 0.55, y: center.y))
            slot.addLine(to: CGPoint(x: center.x + radius * 0.55, y: center.y))
            slot.move(to: CGPoint(x: center.x, y: center.y - radius * 0.55))
            slot.addLine(to: CGPoint(x: center.x, y: center.y + radius * 0.55))
            context.stroke(slot, with: .color(Color(white: 0.3)), lineWidth: max(0.5, 1.4 * scale))
        }
    }
}

// MARK: - Seeded random

/// A small deterministic random generator (a 64-bit LCG), so decorative
/// layouts come out the same on every launch.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// The next value in 0..<1.
    mutating func next() -> CGFloat {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return CGFloat(state >> 11) / CGFloat(UInt64(1) << 53)
    }
}
