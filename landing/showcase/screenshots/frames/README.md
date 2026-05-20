# Device bezel overlays

Drop Apple's official device frame PNGs here. The showcase landing's
device markup expects transparent-screen-cutout PNGs that overlay
exactly on top of the corresponding screenshots.

## Where to get them

1. <https://developer.apple.com/design/resources/> — Apple Design
   Resources (current iOS). Download the Sketch / Figma / Photoshop
   bundle for "iPhone Mockups" and "iPad Mockups".
2. Open in your tool of choice and export the iPhone 17 (or whatever
   the current 6.9" device is) and the iPad Pro 13" bezel as PNGs.
   The screen cutout must be transparent.

## File names this landing expects

| Filename | Use |
|---|---|
| `iphone-17-frame.png` | iPhone hero device + Listen + Summarize medium |
| `ipad-pro-13-frame.png` | (future) iPad-specific screenshots |

## How to enable in the markup

In `landing/showcase/index.html`, each `<div class="device …">`
contains a commented-out `<img class="device-frame-overlay" …>`. Drop
the PNG in, uncomment that line, and the bezel overlays exactly on
top of the screenshot beneath it.

## Sizing

The overlay PNGs scale to 100% of the device wrapper width, so any
aspect-correct resolution works. Apple's PNGs are typically 1290×2796
or larger — that's fine, they downscale cleanly.

## Why this layout

The previous frame was pure CSS (gradient bezel + a black pill for
the dynamic island). It drew its own chrome on top of the screenshot's
real status bar / dynamic island, giving a "frame within a frame"
feel. Layering the actual Apple PNG over the raw screenshot means
the real dynamic island in the capture aligns with the PNG's cutout
and only one set of chrome is visible.
