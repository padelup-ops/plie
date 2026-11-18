//
// OcclusionAvoidance.swift
// RetroCartridge
//
// Keeps custom content clear of occlusion reserved regions, such as the
// inner display's camera while it's active. The HIG: system components
// adapt to reserved regions automatically; "for custom components,
// ReservedRegion provides a way to reposition content away from reserved
// regions", and "when the camera activates, the UI moves aside". Only
// active regions count, so nothing moves while the camera is hidden.
//

import SwiftUI

// MARK: - Insets

/// The padding that keeps a rectangle's content clear of regions covering
/// parts of it. Each region pushes the content in from whichever edge it
/// is nearest to, by as much as it reaches in from that edge.
enum OcclusionInsets {

    /// The furthest a region may push content in, as a share of the
    /// rectangle's size, so a stray region never collapses the content.
    static let maximumShare: CGFloat = 0.4

    static func insets(for bounds: CGRect, avoiding regions: [CGRect]) -> EdgeInsets {
        var insets = EdgeInsets()
        for region in regions {
            let overlap = bounds.intersection(region)
            guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { continue }

            // How far the region reaches in from each edge
            let fromTop = region.maxY - bounds.minY
            let fromBottom = bounds.maxY - region.minY
            let fromLeading = region.maxX - bounds.minX
            let fromTrailing = bounds.maxX - region.minX
            let nearest = min(fromTop, fromBottom, fromLeading, fromTrailing)

            let maxVertical = bounds.height * maximumShare
            let maxHorizontal = bounds.width * maximumShare
            if nearest == fromTop {
                insets.top = max(insets.top, min(fromTop, maxVertical))
            } else if nearest == fromBottom {
                insets.bottom = max(insets.bottom, min(fromBottom, maxVertical))
            } else if nearest == fromLeading {
                insets.leading = max(insets.leading, min(fromLeading, maxHorizontal))
            } else {
                insets.trailing = max(insets.trailing, min(fromTrailing, maxHorizontal))
            }
        }
        return insets
    }
}

// MARK: - Modifier

extension View {
    /// Pads this view's content away from active occlusion regions (a camera
    /// covering part of the display) that fall inside it, easing aside when
    /// one appears. Regions arrive mirrored for the layout direction, so
    /// leading and trailing are already right for right-to-left languages.
    func avoidingOcclusion() -> some View {
        modifier(OcclusionAvoiding())
    }
}

private struct OcclusionAvoiding: ViewModifier {
    func body(content: Content) -> some View {
        GeometryReader { proxy in
            let regions = proxy.reservedRegions(kind: .occlusion)
                .filter(\.isActive)
                .map(\.frame)
            let insets = OcclusionInsets.insets(for: CGRect(origin: .zero, size: proxy.size), avoiding: regions)

            content
                .padding(insets)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .animation(.easeInOut(duration: 0.25), value: insets)
        }
    }
}
