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
// Run from project root:
//
//   swift tools/make_web_screenshots.swift
//
// Then commit + push the spool-website repo to redeploy.

struct WebSlot {
    let source: String       // file in appstore/screenshots/iphone-6.9/
    let outputs: [String]    // file names in spool-website/screenshots/_web/
    let width: CGFloat       // output width
}

let slots: [WebSlot] = [
    WebSlot(source: "01-top-stories.png",      outputs: ["hero-light.png"],                            width: 660),
    WebSlot(source: "02-now-playing.png",      outputs: ["listen-dark.png"],                           width: 560),
    WebSlot(source: "03-editable-prompts.png", outputs: ["summarize-light.png", "summarize-dark.png"], width: 560),
    WebSlot(source: "04-widget.png",           outputs: ["widget-dark.png"],                           width: 560),
    WebSlot(source: "05-customize.png",        outputs: ["settings-light.png"],                        width: 560),
]

let statusBarCropPx: CGFloat = 138
let inputDir  = URL(fileURLWithPath: "appstore/screenshots/iphone-6.9")
let outputDir = URL(fileURLWithPath: "../spool-website/screenshots/_web")

guard FileManager.default.fileExists(atPath: outputDir.deletingLastPathComponent().deletingLastPathComponent().path) else {
    fputs("error: sibling repo ../spool-website not found. Clone github.com/ctaloi/spool-website next to this repo.\n", stderr)
    exit(1)
}
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

for slot in slots {
    let inputURL = inputDir.appendingPathComponent(slot.source)
    guard let src = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else {
        fputs("skip: \(slot.source) missing\n", stderr)
        continue
    }

    let imgW = CGFloat(img.width)
    let imgH = CGFloat(img.height)

    guard let cropped = img.cropping(to: CGRect(
        x: 0, y: statusBarCropPx,
        width: imgW, height: imgH - statusBarCropPx
    )) else { continue }

    let croppedW = CGFloat(cropped.width)
    let croppedH = CGFloat(cropped.height)
    let aspect = croppedW / croppedH

    let outWidth  = slot.width
    let outHeight = (outWidth / aspect).rounded()

    guard let ctx = CGContext(
        data: nil,
        width: Int(outWidth),
        height: Int(outHeight),
        bitsPerComponent: 8,
        bytesPerRow: Int(outWidth) * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { continue }
    ctx.interpolationQuality = .high
    ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: outWidth, height: outHeight))

    guard let resized = ctx.makeImage() else { continue }

    for name in slot.outputs {
        let outURL = outputDir.appendingPathComponent(name)
        guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil) else { continue }
        CGImageDestinationAddImage(dest, resized, nil)
        CGImageDestinationFinalize(dest)
        print("wrote \(name) (\(Int(outWidth))×\(Int(outHeight)))")
    }
}
