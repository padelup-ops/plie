import Photos
import SwiftUI
import UIKit

/// Pixel sizes for the iPhone Duo pair and the story card.
/// Outer 1398×2034 is the cover (466×678 pt at 3×). Inner 1878×2670 is the
/// open display. The card is a 1080×1920 share image, not a wallpaper.
enum WallpaperPixels {
    static let outer = CGSize(width: 1398, height: 2034)
    static let inner = CGSize(width: 1878, height: 2670)
    static let share = CGSize(width: 1080, height: 1920)
}

struct SharePayload: Identifiable {
    let id = UUID()
    let urls: [URL]
}

enum ExportError: Error {
    case draw
}

@MainActor
enum Exporter {
    static func pair(settings: FoldSettings, at date: Date) -> (outer: UIImage, inner: UIImage)? {
        let outer = render(FoldArtwork(settings: settings, mode: .outer, date: date, openAmount: 0, size: WallpaperPixels.outer), size: WallpaperPixels.outer)
        let inner = render(FoldArtwork(settings: settings, mode: .inner, date: date, openAmount: 1, size: WallpaperPixels.inner), size: WallpaperPixels.inner)
        guard let outer, let inner else { return nil }
        return (outer, inner)
    }

    static func card(settings: FoldSettings, outer: UIImage, inner: UIImage) -> UIImage? {
        render(ShareCard(settings: settings, outer: outer, inner: inner), size: WallpaperPixels.share)
    }

    static func writeTemporary(_ image: UIImage, name: String) throws -> URL {
        guard let data = image.pngData() else { throw ExportError.draw }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    enum PhotoResult {
        case saved
        case denied
        case failed
    }

    static func saveToPhotos(_ images: [UIImage], done: @escaping (PhotoResult) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                done(.denied)
                return
            }
            PHPhotoLibrary.shared().performChanges {
                for image in images {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
            } completionHandler: { ok, _ in
                done(ok ? .saved : .failed)
            }
        }
    }

    private static func render<V: View>(_ view: V, size: CGSize) -> UIImage? {
        let content = view
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

struct ShareCard: View {
    var settings: FoldSettings
    var outer: UIImage
    var inner: UIImage

    var body: some View {
        let ink = Ink.resolve(settings)
        ZStack {
            LinearGradient(colors: [ink.raised, ink.ground], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 40) {
                VStack(spacing: 12) {
                    Text("Fold Widgets")
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .tracking(6)
                        .foregroundStyle(ink.mute)
                    Text(NSLocalizedString(settings.theme.nameKey, comment: ""))
                        .font(.system(size: 68, weight: .light, design: .serif))
                        .foregroundStyle(ink.ink)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                HStack(alignment: .top, spacing: 28) {
                    shot(outer, caption: NSLocalizedString("Outer display", comment: ""), ink: ink)
                    shot(inner, caption: NSLocalizedString("Inner display", comment: ""), ink: ink)
                }
                Text("A pair for iPhone Duo")
                    .font(.system(size: 30, weight: .regular, design: .serif))
                    .foregroundStyle(ink.accent)
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 96)
        }
        .frame(width: WallpaperPixels.share.width, height: WallpaperPixels.share.height)
    }

    private func shot(_ image: UIImage, caption: String, ink: Ink) -> some View {
        VStack(spacing: 16) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(ink.accent.opacity(0.4), lineWidth: 2)
                )
            Text(caption)
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .foregroundStyle(ink.mute)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ActivitySheet: UIViewControllerRepresentable {
    var items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
