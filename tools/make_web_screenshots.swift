import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

// Generates the spool-website screenshots/_web/*.png files from the
// App Store source captures. Crops the iOS status bar off the top
// (138px) and downscales to the size the landing page's
// `.device-screenshot` CSS bezel expects. Writes into the sibling
// `spool-website` repo at ../spool-website/screenshots/_web/.
//
// Light/dark pairs:
//   - Light source:  01-top-stories.png       → hero-light.png
//   - Dark source:   01-top-stories-dark.png  → hero-dark.png
//
// When a `-dark.png` source is missing, the script writes the light
// variant under the dark filename too so the website still works —
// the page will just show the same image in both color schemes.
//
// Run from project root:
//
//   swift tools/make_web_screenshots.swift
//
// Then commit + push the spool-website repo to redeploy.

enum Mode: String { case light, dark }

struct WebSlot {
    /// Filename in `appstore/screenshots/iphone-6.9/` for the light
    /// capture. The dark capture (if any) is the same stem with
    /// `-dark` appended before the extension.
    let lightSource: String
    /// Output base name in `spool-website/screenshots/_web/`. Will be
    /// suffixed with `-light.png` and `-dark.png`.
    let outputStem: String
    /// Output width in CSS px.
    let width: CGFloat
}

let slots: [WebSlot] = [
    WebSlot(lightSource: "01-top-stories.png",      outputStem: "hero",      width: 660),
    WebSlot(lightSource: "02-now-playing.png",      outputStem: "listen",    width: 560),
    WebSlot(lightSource: "03-editable-prompts.png", outputStem: "summarize", width: 560),
    WebSlot(lightSource: "04-widget.png",           outputStem: "widget",    width: 560),
    WebSlot(lightSource: "05-customize.png",        outputStem: "settings",  width: 560),
    WebSlot(lightSource: "06-summary.png",          outputStem: "summary",   width: 560),
]

let statusBarCropPx: CGFloat = 138
let inputDir  = URL(fileURLWithPath: "appstore/screenshots/iphone-6.9")
let outputDir = URL(fileURLWithPath: "../spool-website/screenshots/_web")

guard FileManager.default.fileExists(atPath: outputDir.deletingLastPathComponent().deletingLastPathComponent().path) else {
    fputs("error: sibling repo ../spool-website not found. Clone github.com/ctaloi/spool-website next to this repo.\n", stderr)
    exit(1)
}
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

/// Replace the file extension with `-dark.png`, e.g.
/// `02-now-playing.png` → `02-now-playing-dark.png`.
func darkVariant(of lightFilename: String) -> String {
    let nsName = lightFilename as NSString
    let stem = nsName.deletingPathExtension
    let ext = nsName.pathExtension
    return "\(stem)-dark.\(ext)"
}

func render(source: URL, width: CGFloat) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else {
        fputs("skip: \(source.path) missing or unreadable\n", stderr)
        return nil
    }
    let imgW = CGFloat(img.width)
    let imgH = CGFloat(img.height)
    guard let cropped = img.cropping(to: CGRect(
        x: 0, y: statusBarCropPx,
        width: imgW, height: imgH - statusBarCropPx
    )) else { return nil }

    let croppedW = CGFloat(cropped.width)
    let croppedH = CGFloat(cropped.height)
    let aspect = croppedW / croppedH

    let outW = width
    let outH = (outW / aspect).rounded()

    guard let ctx = CGContext(
        data: nil,
        width: Int(outW),
        height: Int(outH),
        bitsPerComponent: 8,
        bytesPerRow: Int(outW) * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.interpolationQuality = .high
    ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: outW, height: outH))
    return ctx.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

for slot in slots {
    let lightSource = inputDir.appendingPathComponent(slot.lightSource)
    let darkSourceName = darkVariant(of: slot.lightSource)
    let darkSource = inputDir.appendingPathComponent(darkSourceName)

    guard let lightImage = render(source: lightSource, width: slot.width) else {
        fputs("error: failed to render light source for \(slot.outputStem)\n", stderr)
        continue
    }
    let lightOut = outputDir.appendingPathComponent("\(slot.outputStem)-light.png")
    writePNG(lightImage, to: lightOut)
    print("wrote \(lightOut.lastPathComponent) (\(lightImage.width)×\(lightImage.height))")

    // Dark variant — use the dark source if present; otherwise reuse
    // the light render so the page's <picture> srcset still resolves.
    let darkOut = outputDir.appendingPathComponent("\(slot.outputStem)-dark.png")
    if FileManager.default.fileExists(atPath: darkSource.path),
       let darkImage = render(source: darkSource, width: slot.width) {
        writePNG(darkImage, to: darkOut)
        print("wrote \(darkOut.lastPathComponent) (\(darkImage.width)×\(darkImage.height))")
    } else {
        writePNG(lightImage, to: darkOut)
        print("wrote \(darkOut.lastPathComponent) (fallback: light copy — drop a \(darkSourceName) into iphone-6.9/ for a real dark capture)")
    }
}
