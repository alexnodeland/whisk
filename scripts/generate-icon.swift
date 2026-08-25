// generate-icon.swift — render Whisk.icns from code.
//
// Draws the app icon (a white whisk on an indigo-violet gradient squircle) at
// 1024px, then emits every size into an iconset and runs iconutil. Re-run only
// when deliberately changing the icon:
//
//   swift scripts/generate-icon.swift && iconutil -c icns build/Whisk.iconset -o Whisk.icns

import AppKit

let canvas: CGFloat = 1024

func drawIcon(into size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let scale = size / canvas

    // Background squircle with the standard macOS icon margin.
    let margin: CGFloat = 100 * scale
    let rect = NSRect(x: margin, y: margin, width: size - 2 * margin, height: size - 2 * margin)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: 185 * scale, yRadius: 185 * scale)
    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.31, green: 0.27, blue: 0.90, alpha: 1),
        ending: NSColor(calibratedRed: 0.62, green: 0.30, blue: 0.88, alpha: 1))!
    gradient.draw(in: squircle, angle: -60)

    // Soft sparkle accents.
    NSColor(calibratedWhite: 1, alpha: 0.22).setFill()
    for (x, y, r) in [(300.0, 740.0, 26.0), (740.0, 700.0, 18.0), (680.0, 300.0, 22.0)] {
        NSBezierPath(
            ovalIn: NSRect(
                x: (x - r) * scale, y: (y - r) * scale, width: 2 * r * scale, height: 2 * r * scale)
        ).fill()
    }

    // The whisk: a rounded handle and four wire loops meeting at the tip.
    NSColor.white.setStroke()
    NSColor.white.setFill()

    let handle = NSBezierPath(
        roundedRect: NSRect(x: 478 * scale, y: 700 * scale, width: 68 * scale, height: 190 * scale),
        xRadius: 34 * scale, yRadius: 34 * scale)
    handle.fill()

    let top = NSPoint(x: 512 * scale, y: 710 * scale)
    let tip = NSPoint(x: 512 * scale, y: 190 * scale)
    for bulge: CGFloat in [-190, -95, 95, 190] {
        let wire = NSBezierPath()
        wire.lineWidth = 30 * scale
        wire.lineCapStyle = .round
        wire.move(to: top)
        wire.curve(
            to: tip,
            controlPoint1: NSPoint(x: (512 + bulge) * scale, y: 620 * scale),
            controlPoint2: NSPoint(x: (512 + bulge) * scale, y: 300 * scale))
        wire.stroke()
    }
    let center = NSBezierPath()
    center.lineWidth = 30 * scale
    center.lineCapStyle = .round
    center.move(to: top)
    center.line(to: tip)
    center.stroke()

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, pixels: Int, to url: URL) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let iconset = URL(fileURLWithPath: "build/Whisk.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    let image = drawIcon(into: CGFloat(base))
    writePNG(image, pixels: base, to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(image, pixels: base * 2, to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print("iconset written to build/Whisk.iconset")
