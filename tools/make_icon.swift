import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

// Renders a 1024×1024 HN Skim app icon: a single bold orange lightning bolt
// on a clean white background. No gradients, no shadows, no text — meant to
// read crisply at every home-screen size.

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

// Image-space coords (y=0 at top) so values below match a designer's mental
// model: y increases downward.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

// Background — solid white.
ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

// Bolt — six-vertex zig-zag polygon, sized at ~88% of the canvas vertically
// so it fills the iOS icon mask comfortably without touching the corners.
// Vertex order is CW in image-space (y down). The shape: narrow at the top
// peak, flares to a wide waist with a Z-notch, narrows again to the bottom
// peak.
let bolt: [CGPoint] = [
    CGPoint(x: 520, y:  84),   // top peak
    CGPoint(x: 180, y: 512),   // upper waist, outer-left
    CGPoint(x: 380, y: 512),   // upper waist, inner (left notch jogs right)
    CGPoint(x: 480, y: 940),   // bottom peak
    CGPoint(x: 820, y: 512),   // lower waist, outer-right
    CGPoint(x: 620, y: 512),   // lower waist, inner (right notch jogs left)
]

let path = CGMutablePath()
path.move(to: bolt[0])
for i in 1..<bolt.count { path.addLine(to: bolt[i]) }
path.closeSubpath()

// HN-orange bolt fill — matches Theme.accent in the SwiftUI app.
ctx.setFillColor(CGColor(red: 1.0, green: 0.40, blue: 0.0, alpha: 1.0))
ctx.addPath(path)
ctx.fillPath()

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
