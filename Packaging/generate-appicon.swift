//
//  generate-appicon.swift
//  Renders the PeaceTimer app icon (glass squircle + countdown dial + ">_" prompt)
//  into an .iconset, which `iconutil` then packs into Resources/AppIcon.icns.
//
//  The native `.icon` (Assets.xcassets/AppIcon.icon) provides the layered Liquid
//  Glass look on macOS 26; this .icns is the classic bundle icon that Finder, the
//  Dock, and the DMG volume icon use everywhere. Regenerate with:
//
//      swift Packaging/generate-appicon.swift
//      iconutil -c icns Packaging/AppIcon.iconset -o Resources/AppIcon.icns
//

import AppKit

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16",      16), ("icon_16x16@2x",    32),
    ("icon_32x32",      32), ("icon_32x32@2x",    64),
    ("icon_128x128",   128), ("icon_128x128@2x", 256),
    ("icon_256x256",   256), ("icon_256x256@2x", 512),
    ("icon_512x512",   512), ("icon_512x512@2x",1024),
]

/// Draw the icon into a `side`×`side` bitmap. All geometry is expressed as a
/// fraction of the canvas so every rendition is pixel-consistent.
func render(side: CGFloat) -> NSBitmapImageRep {
    let px = Int(side)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("rep") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!

    // macOS app-icon squircle: ~22.37% corner radius, with a small margin so the
    // icon sits on Apple's grid rather than filling the whole tile.
    let margin = side * 0.055
    let box = NSRect(x: margin, y: margin, width: side - margin * 2, height: side - margin * 2)
    let radius = box.width * 0.2237
    let squircle = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)

    // Blue glass base.
    NSGradient(colors: [
        NSColor(srgbRed: 0.498, green: 0.776, blue: 1.0, alpha: 1),
        NSColor(srgbRed: 0.306, green: 0.608, blue: 1.0, alpha: 1),
        NSColor(srgbRed: 0.416, green: 0.357, blue: 1.0, alpha: 1),
    ], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
        .draw(in: squircle, angle: -55)

    // Top sheen for depth — drawn across the FULL box so it fades out smoothly
    // instead of leaving a hard seam at the halfway point.
    squircle.setClip()
    NSGradient(colors: [NSColor(white: 1, alpha: 0.28), NSColor(white: 1, alpha: 0)],
               atLocations: [0, 1], colorSpace: .sRGB)!
        .draw(in: box, angle: -90)

    let c = NSPoint(x: side / 2, y: side / 2)
    let dialR = side * 0.30
    let lw = side * 0.055

    // Dial ring (dim track).
    let ring = NSBezierPath()
    ring.appendArc(withCenter: c, radius: dialR, startAngle: 0, endAngle: 360)
    ring.lineWidth = lw
    NSColor(white: 1, alpha: 0.32).setStroke()
    ring.stroke()

    // Countdown progress arc — 70%, starting at 12 o'clock going clockwise.
    let arc = NSBezierPath()
    arc.appendArc(withCenter: c, radius: dialR,
                  startAngle: 90, endAngle: 90 - 252, clockwise: true)
    arc.lineWidth = lw
    arc.lineCapStyle = .round
    NSColor.white.setStroke()
    arc.stroke()

    // Terminal ">" chevron.
    let chevW = side * 0.085, chevH = side * 0.115
    let chevX = c.x - side * 0.075
    let chev = NSBezierPath()
    chev.move(to: NSPoint(x: chevX - chevW / 2, y: c.y + chevH / 2))
    chev.line(to: NSPoint(x: chevX + chevW / 2, y: c.y))
    chev.line(to: NSPoint(x: chevX - chevW / 2, y: c.y - chevH / 2))
    chev.lineWidth = side * 0.045
    chev.lineCapStyle = .round
    chev.lineJoinStyle = .round
    NSColor.white.setStroke()
    chev.stroke()

    // Terminal "_" cursor.
    let cursorW = side * 0.095, cursorH = side * 0.037
    let cursor = NSBezierPath(roundedRect:
        NSRect(x: chevX + chevW * 0.75, y: c.y - chevH / 2 - cursorH * 0.2,
               width: cursorW, height: cursorH),
        xRadius: cursorH / 2, yRadius: cursorH / 2)
    NSColor.white.setFill()
    cursor.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = URL(fileURLWithPath: "Packaging/AppIcon.iconset", isDirectory: true)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

for (name, px) in sizes {
    let rep = render(side: CGFloat(px))
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
    try! png.write(to: out.appendingPathComponent("\(name).png"))
    print("wrote \(name).png (\(px)×\(px))")
}
print("iconset ready → run: iconutil -c icns Packaging/AppIcon.iconset -o Resources/AppIcon.icns")
