import SwiftUI
import AppKit
import ImageIO

/// Downloads images. Nothing is cached, in memory or on disk: each image lives only
/// while the view showing it is on screen.
final class ImageLoader: @unchecked Sendable {
    static let shared = ImageLoader()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil
        session = URLSession(configuration: config)
    }

    /// `maxPixel`: the longest side the image is shown at, in pixels. The picture is
    /// decoded straight to that size (Apple's image guidance), so a 1200-pixel cover
    /// shown as a small thumbnail doesn't keep megabytes of pixels in memory.
    func load(_ url: String, maxPixel: Int = 720) async -> NSImage? {
        if let img = await fetch(url, maxPixel) { return img }
        // Some resized thumbnail variants don't exist: fall back to the original size.
        if let base = Self.unsized(url), base != url { return await fetch(base, maxPixel) }
        return nil
    }

    /// Decodes (and shrinks) in the background, so the main thread never decodes images.
    private static func decode(_ data: Data, maxPixel: Int) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(32, maxPixel),
        ] as [CFString: Any] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private func fetch(_ url: String, _ maxPixel: Int) async -> NSImage? {
        guard let u = URL(string: url) else { return nil }
        for attempt in 0..<3 {
            if Task.isCancelled { return nil }
            var req = URLRequest(url: u)
            req.timeoutInterval = 20
            if let result = try? await session.data(for: req),
               case let (data, resp) = result,
               let http = resp as? HTTPURLResponse {
                if (200..<300).contains(http.statusCode), let image = Self.decode(data, maxPixel: maxPixel) { return image }
                if (400..<500).contains(http.statusCode) { return nil }
            }
            try? await Task.sleep(nanoseconds: UInt64(400_000_000 * (attempt + 1)))
        }
        return nil
    }

    /// "…=w544-h544-l90-rj" → "…" for googleusercontent / ggpht thumbnails.
    private static func unsized(_ url: String) -> String? {
        guard url.contains("googleusercontent.com") || url.contains("ggpht.com"),
              let eq = url.lastIndex(of: "=") else { return nil }
        return String(url[..<eq])
    }
}

/// Async image that fills its frame (crop) and shows a neutral placeholder while loading.
struct RemoteImage: View {
    let url: String?
    var placeholderIcon: String = "music.note"

    @ViewState var image: NSImage? = nil
    @ViewState var loadedURL: String? = nil
    @ViewState var side: CGFloat = 0

    /// Pixels needed for the size this view is shown at (Retina), within sane bounds.
    private func pixelBudget() async -> Int {
        if side <= 0 { try? await Task.sleep(nanoseconds: 40_000_000) }   // wait for layout
        guard side > 0 else { return 720 }
        return min(1600, max(96, Int((side * 2).rounded(.up))))
    }

    var body: some View {
        Color.subtleFill
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { side = max(g.size.width, g.size.height) }
                    .onChange(of: g.size) { _, s in
                        // Only a clearly bigger frame matters (the image is reloaded sharper).
                        let m = max(s.width, s.height)
                        if m > side * 1.5 || side == 0 { side = m }
                    }
            })
            .overlay {
                let shown = loadedURL == url ? image : nil
                ZStack {
                    if let img = shown {
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                            .id(url)
                            .transition(.opacity)
                    } else {
                        Image(systemName: placeholderIcon)
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(.tertiary)
                            .transition(.opacity)
                    }
                }
                // Images fade in when they arrive and cross-fade when the URL changes.
                .animation(.easeInOut(duration: 0.35), value: shown == nil ? "" : (url ?? ""))
            }
            .clipped()
            .task(id: url) {
                guard let url else { image = nil; loadedURL = nil; return }
                if loadedURL == url, image != nil { return }
                let budget = await pixelBudget()
                guard !Task.isCancelled else { return }
                var img = await ImageLoader.shared.load(url, maxPixel: budget)
                if img == nil && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    img = await ImageLoader.shared.load(url, maxPixel: budget)
                }
                guard !Task.isCancelled else { return }
                image = img
                loadedURL = url
            }
            // Off screen: let the picture go right away.
            .onDisappear { image = nil; loadedURL = nil }
    }
}

/// Picks a vivid "dominant" colour from artwork, used for gradient headers.
enum ColorExtractor {
    static func color(for url: String?) async -> Color? {
        guard let url, let image = await ImageLoader.shared.load(url, maxPixel: 48),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return Color(nsColor: dominant(cg))
    }

    static func dominant(_ image: CGImage) -> NSColor {
        let w = 24, h = 24
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .darkGray }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let raw = ctx.data else { return .darkGray }
        let px = raw.bindMemory(to: UInt8.self, capacity: w * h * 4)

        var bins = [(weight: Double, r: Double, g: Double, b: Double)](repeating: (0, 0, 0, 0), count: 12)
        var tr = 0.0, tg = 0.0, tb = 0.0
        for i in stride(from: 0, to: w * h * 4, by: 4) {
            let r = Double(px[i]) / 255, g = Double(px[i + 1]) / 255, b = Double(px[i + 2]) / 255
            tr += r; tg += g; tb += b
            var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
            NSColor(srgbRed: r, green: g, blue: b, alpha: 1).getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
            guard bri > 0.15, bri < 0.98 else { continue }
            let weight = Double(sat * sat) * (0.3 + Double(bri))
            let bin = min(11, Int(hue * 12))
            bins[bin].weight += weight
            bins[bin].r += r * weight
            bins[bin].g += g * weight
            bins[bin].b += b * weight
        }

        let best = bins.max { $0.weight < $1.weight } ?? (0, 0, 0, 0)
        let vivid = best.weight > 2
        let base: NSColor
        if vivid {
            base = NSColor(srgbRed: best.r / best.weight, green: best.g / best.weight, blue: best.b / best.weight, alpha: 1)
        } else {
            let n = Double(w * h)
            base = NSColor(srgbRed: tr / n, green: tg / n, blue: tb / n, alpha: 1)
        }
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
        (base.usingColorSpace(.sRGB) ?? base).getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
        sat = vivid ? min(max(sat, 0.35), 0.8) : min(sat, 0.25)
        bri = min(max(bri, 0.38), 0.6)
        return NSColor(hue: hue, saturation: sat, brightness: bri, alpha: 1)
    }
}
