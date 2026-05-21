import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

// Renders the 1024×1024 Spool app icon: three left-aligned, pill-shaped
// bars of decreasing length and opacity on a tinted field. Three modes:
//
//   light   — HN orange field, white pills (the new default; matches
//             the landing-site favicon).
//   dark    — near-black field, HN orange pills (iOS dark-appearance
//             home-screen variant).
//   tinted  — transparent field, light pills (iOS reads the alpha
//             silhouette and renders it through the user's chosen
//             tint color).
//
// Usage: swift make_icon.swift [light|dark|tinted] [output-path]

enum IconMode: String { case light, dark, tinted }

let argMode = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1].lowercased()
    : "light"
guard let mode = IconMode(rawValue: argMode) else {
    fputs("Unknown mode '\(argMode)'. Use: light | dark | tinted\n", stderr)
    exit(1)
}
let outArg = CommandLine.arguments.count > 2
    ? CommandLine.arguments[2]
    : "icon-1024-\(mode.rawValue).png"

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

ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

// MARK: - Background + pill colors per appearance

let orange = CGColor(red: 1.0, green: 0.40, blue: 0.0, alpha: 1.0)
let darkBG = CGColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1.0)
let white = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)

let background: CGColor?
let pillBase: CGColor
switch mode {
case .light:
    background = orange
    pillBase = white
case .dark:
    background = darkBG
    pillBase = orange
case .tinted:
    // Transparent — iOS fills with the user's selected tint behind
    // the white silhouette pills.
    background = nil
    pillBase = white
}

if let background {
    ctx.setFillColor(background)
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
}

// MARK: - Pills

let barHeight: CGFloat = 110
let cornerRadius: CGFloat = barHeight / 2
let gap: CGFloat = 96

// Three pills with descending width AND descending opacity. The fade
// communicates "skim a feed" — strong top story, lighter rest.
let bars: [(width: CGFloat, opacity: CGFloat)] = [
    (720, 1.0),
    (540, 0.70),
    (360, 0.40),
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
    let comps = pillBase.components ?? [1, 1, 1, 1]
    let color = CGColor(
        red: comps[0], green: comps[1], blue: comps[2],
        alpha: bar.opacity
    )
    ctx.setFillColor(color)
    ctx.addPath(path)
    ctx.fillPath()
}

// MARK: - Write PNG

let outURL = URL(fileURLWithPath: outArg)
guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(
          outURL as CFURL, UTType.png.identifier as CFString, 1, nil
      )
else { fatalError("destination") }
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("write failed") }
print("wrote \(outURL.path) (\(mode.rawValue))")
