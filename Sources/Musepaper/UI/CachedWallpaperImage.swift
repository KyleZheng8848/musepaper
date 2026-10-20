import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum ImageCacheRole: String, CaseIterable {
    case thumbnail
    case candidate
    case preview
    case lightbox

    var maxPixel: CGFloat {
        switch self {
        case .thumbnail: return 480
        case .candidate: return 720
        case .preview: return 1600
        case .lightbox: return 2880
        }
    }
}

final class WallpaperImageCache: @unchecked Sendable {
    static let shared = WallpaperImageCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 256
        cache.totalCostLimit = 256 * 1024 * 1024
    }

    func image(path: String, role: ImageCacheRole) -> NSImage? {
        cache.object(forKey: key(path, role))
    }

    func store(_ image: NSImage, path: String, role: ImageCacheRole) {
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: key(path, role), cost: cost)
    }

    func evict(path: String) {
        for role in ImageCacheRole.allCases {
            cache.removeObject(forKey: key(path, role))
        }
    }

    private func key(_ path: String, _ role: ImageCacheRole) -> NSString {
        "\(role.rawValue)|\(path)" as NSString
    }

    static func downsample(path: String, maxPixel: CGFloat) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// Compact JPEG for vision tagging — keeps upload small without wrecking scene cues.
    static func jpegThumbnail(path: String, maxPixel: CGFloat = 512, quality: CGFloat = 0.55) -> Data? {
        let url = URL(fileURLWithPath: path)
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, cgImage, props as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

struct CachedWallpaperImage: View {
    let path: String?
    var role: ImageCacheRole = .thumbnail
    var fill: Bool = true

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color.white.opacity(0.04)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fill ? .fill : .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: "\(role.rawValue)|\(path ?? "")") {
            await load()
        }
    }

    private func load() async {
        guard let path, !path.isEmpty else {
            image = nil
            return
        }
        if let cached = WallpaperImageCache.shared.image(path: path, role: role) {
            image = cached
            return
        }
        let maxPixel = role.maxPixel
        let loaded = await Task.detached(priority: .userInitiated) {
            DownsampledImage(WallpaperImageCache.downsample(path: path, maxPixel: maxPixel))
        }.value.image
        if let loaded {
            WallpaperImageCache.shared.store(loaded, path: path, role: role)
        }
        image = loaded
    }
}

private struct DownsampledImage: @unchecked Sendable {
    let image: NSImage?
    init(_ image: NSImage?) { self.image = image }
}
