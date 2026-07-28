//
//  generate-dmg-background.swift
//  Draws the DMG installer background — the classic "drag the app onto Applications"
//  window: soft gradient, an arrow between the two icon spots, and a hint line.
//  Regenerate (CI does this automatically) with:
//
//      swift Packaging/generate-dmg-background.swift
//      tiffutil -cathidpicheck Packaging/dmg-background.png \
//               Packaging/dmg-background@2x.png \
//               -out Packaging/dmg-background.tiff
//
//  Geometry must stay in sync with the create-dmg call in
//  .github/workflows/build-and-release.yml:
//    window content 660×400, icons at (165,190) and (495,190), size 128.
//

import AppKit

let baseW = 660.0, baseH = 400.0
let appName = "PeaceTimer"

func draw(scale: CGFloat, to url: URL) {
    let w = Int(baseW * scale), h = Int(baseH * scale)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("rep") }
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.cgContext.scaleBy(x: scale, y: scale)

    // Soft neutral gradient (reads fine over light AND dark Finder chrome).
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.965, green: 0.969, blue: 0.976, alpha: 1),
        NSColor(calibratedRed: 0.905, green: 0.912, blue: 0.925, alpha: 1),
    ])!
    gradient.draw(in: NSRect(x: 0, y: 0, width: baseW, height: baseH), angle: -90)

    // Faint PeaceTimer-blue wash at the top for a bit of depth.
    NSColor(calibratedRed: 0.39, green: 0.74, blue: 1.0, alpha: 0.07).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: baseH - 120, width: baseW, height: 120)).fill()

    // Finder icon centers use y-down 190 → CG y-up: 400-190 = 210.
    let arrowY = 210.0
    let arrow = NSBezierPath()
    arrow.lineWidth = 14
    arrow.lineCapStyle = .round
    arrow.move(to: NSPoint(x: 262, y: arrowY))
    arrow.line(to: NSPoint(x: 386, y: arrowY))
    NSColor(calibratedWhite: 0.72, alpha: 1).setStroke()
    arrow.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 380, y: arrowY + 26))
    head.line(to: NSPoint(x: 418, y: arrowY))
    head.line(to: NSPoint(x: 380, y: arrowY - 26))
    head.close()
    NSColor(calibratedWhite: 0.72, alpha: 1).setFill()
    head.fill()

    // Hint line under the icon labels.
    let hint = "Drag \(appName) into Applications to install"
    let style = NSMutableParagraphStyle(); style.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium),
        .foregroundColor: NSColor(calibratedWhite: 0.5, alpha: 1),
        .paragraphStyle: style,
    ]
    (hint as NSString).draw(in: NSRect(x: 0, y: 52, width: baseW, height: 24), withAttributes: attrs)

    NSGraphicsContext.restoreGraphicsState()

    rep.size = NSSize(width: baseW, height: baseH)   // stamp DPI so @2x scales right
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
    try! png.write(to: url)
    print("wrote \(url.lastPathComponent) (\(w)×\(h))")
}

let dir = URL(fileURLWithPath: "Packaging", isDirectory: true)
draw(scale: 1, to: dir.appendingPathComponent("dmg-background.png"))
draw(scale: 2, to: dir.appendingPathComponent("dmg-background@2x.png"))
