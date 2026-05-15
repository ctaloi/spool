import UIKit
import CoreImage

/// Pulls a "brand color" out of an OG image. Naive average colors are
/// usually muddy — a saturated brand logo on a white background averages
/// to off-white with a faint pink, which isn't useful for accenting.
///
/// We compromise: take the area-average for speed, then nudge the result
/// toward usable saturation/brightness. Good enough for the subtle
/// thumbnail-stroke and detail-page hero tinting we do with it.
actor DominantColor {
    static let shared = DominantColor()

    /// Cached extracted colors, keyed by source image URL. Bounded so
    /// long browsing sessions don't grow forever.
    private let cache: NSCache<NSURL, UIColor> = {
        let c = NSCache<NSURL, UIColor>()
        c.countLimit = 500
        return c
    }()

    private let ciContext = CIContext(options: [.workingColorSpace: NSNull()])

    /// Extract a tasteful accent color from `image`, caching by `url` so
    /// repeated thumbnail renders are free. Returns nil on extraction
    /// failure or for images we'd rather not key off (e.g. fully white
    /// favicon-on-white).
    func extract(from image: UIImage, url: URL) async -> UIColor? {
        if let hit = cache.object(forKey: url as NSURL) {
            return hit
        }
        guard let cgImage = image.cgImage else { return nil }
        let inputImage = CIImage(cgImage: cgImage)
        let extent = inputImage.extent
        let inputExtent = CIVector(x: extent.origin.x,
                                   y: extent.origin.y,
                                   z: extent.size.width,
                                   w: extent.size.height)
        guard let filter = CIFilter(
            name: "CIAreaAverage",
            parameters: [
                kCIInputImageKey: inputImage,
                kCIInputExtentKey: inputExtent
            ]
        ), let output = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        let r = CGFloat(bitmap[0]) / 255
        let g = CGFloat(bitmap[1]) / 255
        let b = CGFloat(bitmap[2]) / 255
        let raw = UIColor(red: r, green: g, blue: b, alpha: 1)
        let polished = Self.polish(raw)
        cache.setObject(polished, forKey: url as NSURL)
        return polished
    }

    /// Clamp brightness into a readable band and floor saturation so
    /// near-grayscale averages don't render as flat gray. Keeps the hue
    /// from the source — that's the part with character.
    private static func polish(_ color: UIColor) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &br, alpha: &a)
        // Floor saturation so logo-on-white doesn't produce a desaturated
        // ghost; ceiling so brand colors don't blow out as neon.
        let polishedS = min(max(s, 0.35), 0.85)
        // Clamp brightness so it reads against both light and dark UI.
        let polishedB = min(max(br, 0.45), 0.80)
        return UIColor(hue: h, saturation: polishedS, brightness: polishedB, alpha: a)
    }
}
