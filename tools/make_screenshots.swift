import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

// Renders the App Store marketing screenshots: a bold title and one-line
// subtitle on a soft cream field, with the raw iPhone screenshot floating
// below in a rounded card with a subtle drop shadow.
//
// Run from the project root:
//
//   swift tools/make_screenshots.swift
//
// Inputs:  appstore/screenshots/iphone-6.9/{01..05}-*.png  (1320×2868)
// Outputs: appstore/screenshots/iphone-6.9-marketed/        (1320×2868)
//          appstore/screenshots/iphone-6.5-marketed/        (1284×2778, resized)

struct Slide {
    let input: String
    let title: String
}

let slides: [Slide] = [
    Slide(input: "01-top-stories.png",      title: "Read."),
    Slide(input: "02-now-playing.png",      title: "Listen."),
    Slide(input: "03-editable-prompts.png", title: "Edit."),
    Slide(input: "04-widget.png",           title: "Pin it."),
    Slide(input: "05-customize.png",        title: "Yours."),
]

let canvasWidth: CGFloat = 1320
let canvasHeight: CGFloat = 2868

// Top-anchored layout (px from top of canvas).
let topPadding: CGFloat = 240
let titleFontSize: CGFloat = 168
let titleKern: CGFloat = -3
let titleToScreenshotGap: CGFloat = 130
let bottomPadding: CGFloat = 150
let screenshotSidePadding: CGFloat = 100
let screenshotCornerRadius: CGFloat = 64
let shadowOffset = CGSize(width: 0, height: -28)
let shadowBlur: CGFloat = 100
let cardBorderWidth: CGFloat = 1.5

// Palette — warmer cream, near-black title, HN orange accent for the
// signature trailing period that ties the five slides together.
let bg          = NSColor(red: 0.95, green: 0.91, blue: 0.85, alpha: 1.0)
let titleColor  = NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0)
let accentColor = NSColor(red: 1.00, green: 0.40, blue: 0.00, alpha: 1.0)
let shadowColor = NSColor(white: 0, alpha: 0.28)
let borderColor = NSColor(red: 0.72, green: 0.65, blue: 0.55, alpha: 0.45)

let inputDir = URL(fileURLWithPath: "appstore/screenshots/iphone-6.9")
let outputDir6_9 = URL(fileURLWithPath: "appstore/screenshots/iphone-6.9-marketed")
let outputDir6_5 = URL(fileURLWithPath: "appstore/screenshots/iphone-6.5-marketed")
try? FileManager.default.createDirectory(at: outputDir6_9, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: outputDir6_5, withIntermediateDirectories: true)

func renderSlide(_ slide: Slide) -> CGImage? {
    guard let ctx = CGContext(
        data: nil,
        width: Int(canvasWidth),
        height: Int(canvasHeight),
        bitsPerComponent: 8,
        bytesPerRow: Int(canvasWidth) * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // Background fill.
    ctx.setFillColor(bg.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))

    // Push an AppKit graphics context so NSAttributedString.draw uses our
    // CGContext. We deliberately keep `flipped: false` — y grows upward,
    // matching CG — so we convert "y from top" by subtracting from height.
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

    let centered = NSMutableParagraphStyle()
    centered.alignment = .center

    // Build the title as an attributed string with the trailing period
    // (if any) recoloured in HN orange — that small accent stitches the
    // five slides together visually without going loud.
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: titleFontSize, weight: .heavy),
        .foregroundColor: titleColor,
        .kern: titleKern,
        .paragraphStyle: centered,
    ]
    let titleStr = NSMutableAttributedString(string: slide.title, attributes: titleAttrs)
    if slide.title.hasSuffix(".") {
        let dotRange = NSRange(location: (slide.title as NSString).length - 1, length: 1)
        titleStr.addAttribute(.foregroundColor, value: accentColor, range: dotRange)
    }

    let titleHeight = titleStr.size().height
    let titleYFromBottom = canvasHeight - topPadding - titleHeight
    titleStr.draw(
        with: CGRect(x: 0, y: titleYFromBottom, width: canvasWidth, height: titleHeight + 10),
        options: [.usesLineFragmentOrigin],
        context: nil
    )

    NSGraphicsContext.restoreGraphicsState()

    // Screenshot — load, fit, draw with rounded corners + shadow.
    let inputURL = inputDir.appendingPathComponent(slide.input)
    guard let src = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else {
        fputs("failed to load \(inputURL.path)\n", stderr)
        return nil
    }

    let imgW = CGFloat(img.width)
    let imgH = CGFloat(img.height)

    // Crop the iOS status bar off the top of the source before drawing.
    // Avoiding the status bar entirely is cleaner than trying to render
    // a normalized one — no time/battery/carrier inconsistencies, no
    // CarPlay or call indicators leaking through.
    let statusBarCropPx: CGFloat = 138
    let croppedImg = img.cropping(to: CGRect(
        x: 0, y: statusBarCropPx,
        width: imgW, height: imgH - statusBarCropPx
    )) ?? img
    let croppedW = CGFloat(croppedImg.width)
    let croppedH = CGFloat(croppedImg.height)
    let imgAspect = croppedW / croppedH

    let availableHeight = titleYFromBottom - titleToScreenshotGap - bottomPadding
    let availableWidth  = canvasWidth - 2 * screenshotSidePadding

    var ssH = availableHeight
    var ssW = ssH * imgAspect
    if ssW > availableWidth {
        ssW = availableWidth
        ssH = ssW / imgAspect
    }

    let ssX = (canvasWidth - ssW) / 2
    let ssY = bottomPadding
    let ssRect = CGRect(x: ssX, y: ssY, width: ssW, height: ssH)

    // Drop shadow — fill a same-shape opaque path under the screenshot so
    // CG knows what silhouette to cast.
    ctx.saveGState()
    ctx.setShadow(offset: shadowOffset, blur: shadowBlur, color: shadowColor.cgColor)
    ctx.addPath(CGPath(roundedRect: ssRect, cornerWidth: screenshotCornerRadius, cornerHeight: screenshotCornerRadius, transform: nil))
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // The screenshot itself, clipped to the rounded rect.
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: ssRect, cornerWidth: screenshotCornerRadius, cornerHeight: screenshotCornerRadius, transform: nil))
    ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(croppedImg, in: ssRect)
    ctx.restoreGState()

    // Hairline card border — separates the screenshot card from the
    // warm-cream backdrop. Drawn on top of the screenshot so the corner
    // arc reads as continuous against the surrounding fill.
    ctx.saveGState()
    let borderInset = cardBorderWidth / 2
    let borderRect = ssRect.insetBy(dx: borderInset, dy: borderInset)
    ctx.addPath(CGPath(roundedRect: borderRect, cornerWidth: screenshotCornerRadius, cornerHeight: screenshotCornerRadius, transform: nil))
    ctx.setStrokeColor(borderColor.cgColor)
    ctx.setLineWidth(cardBorderWidth)
    ctx.strokePath()
    ctx.restoreGState()

    return ctx.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

func resize(_ image: CGImage, to width: Int, height: Int) -> CGImage? {
    guard let ctx = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()
}

for slide in slides {
    guard let image = renderSlide(slide) else { continue }
    writePNG(image, to: outputDir6_9.appendingPathComponent(slide.input))
    if let smaller = resize(image, to: 1284, height: 2778) {
        writePNG(smaller, to: outputDir6_5.appendingPathComponent(slide.input))
    }
    print("wrote \(slide.input)")
}
