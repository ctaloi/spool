import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

// Renders the 1024×1024 HN Skim app icon: three left-aligned, pill-shaped
// bars of decreasing length on a soft white field. The top bar is HN
// orange (the ranked "top story"); the bars below fade to gray, signaling
// a feed being skimmed. No gradients, no text — meant to read crisply at
// every home-screen size and to look unlike any other reader app on the
// home screen.

let size: CGFloat = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: Int(size), height: Int(size),
    bitsPerComponent: 8,
    bytesPerRow: Int(size) * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("ctx") }

// Image-space coords (y=0 at top).
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

// Background — clean off-white. Pure #FFFFFF reads as harsh on OLED;
// a hair-warm tint keeps the bars feeling crisp without burning out.
ctx.setFillColor(CGColor(red: 0.985, green: 0.985, blue: 0.982, alpha: 1.0))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

// Stack geometry. Three pill bars, all left-aligned at the same x so
// the silhouette reads as a ragged-right "list".
let barHeight: CGFloat = 110
let cornerRadius: CGFloat = barHeight / 2  // full pill
let gap: CGFloat = 96

let bars: [(width: CGFloat, color: CGColor)] = [
    // Top bar — HN orange, longest. The "Top Story".
    (720, CGColor(red: 1.0, green: 0.40, blue: 0.0, alpha: 1.0)),
    // Middle bar — slate gray, medium length.
    (540, CGColor(red: 0.42, green: 0.46, blue: 0.52, alpha: 1.0)),
    // Bottom bar — light gray, shortest, fading out.
    (360, CGColor(red: 0.72, green: 0.74, blue: 0.78, alpha: 1.0)),
]

let widestWidth = bars.map(\.width).max() ?? 0
let leftX = (size - widestWidth) / 2
let stackHeight = CGFloat(bars.count) * barHeight + CGFloat(bars.count - 1) * gap
let stackTop = (size - stackHeight) / 2

for (i, bar) in bars.enumerated() {
    let y = stackTop + CGFloat(i) * (barHeight + gap)
    let rect = CGRect(x: leftX, y: y, width: bar.width, height: barHeight)
    let path = CGPath(
        roundedRect: rect,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )
    ctx.setFillColor(bar.color)
    ctx.addPath(path)
    ctx.fillPath()
}

// Write PNG.
let outArg = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "icon-1024.png"
let outURL = URL(fileURLWithPath: outArg)
guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(
          outURL as CFURL, UTType.png.identifier as CFString, 1, nil
      )
else { fatalError("destination") }
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("write failed") }
print("wrote \(outURL.path)")
