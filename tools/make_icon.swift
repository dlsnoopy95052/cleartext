// Draws the ClearText app icon. Usage: swift make_icon.swift <output-dir-for-iconset>
import AppKit

func c(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}

func draw() {
    let ctx = NSGraphicsContext.current!.cgContext
    // Background squircle with soft shadow (standard macOS icon grid: 824 px body on a 1024 canvas)
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: c(0x000000, 0.35).cgColor)
    c(0x5B5BD6).setFill()
    NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185).fill()
    ctx.restoreGState()
    let bg = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSGradient(colors: [c(0x7A7AF0), c(0x4A55C8), c(0x2B9DB8)], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
        .draw(in: bg, angle: -60)

    // Paper
    let paper = NSRect(x: 280, y: 190, width: 464, height: 620)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: c(0x10124A, 0.45).cgColor)
    c(0xFFFFFF).setFill()
    NSBezierPath(roundedRect: paper, xRadius: 38, yRadius: 38).fill()
    ctx.restoreGState()

    // Heading bars (two levels, like the app's headings)
    c(0x5B5BD6).setFill()
    NSBezierPath(roundedRect: NSRect(x: 332, y: 726, width: 250, height: 36), xRadius: 18, yRadius: 18).fill()
    // Text lines with alternating bands (the app's striped rows); slot 3 is a sub-heading
    let widths: [CGFloat] = [360, 320, 360, 0, 330, 350, 290, 340]
    var y: CGFloat = 664
    for (i, w) in widths.enumerated() {
        if i % 2 == 1 {
            c(0xDCE3F2).setFill()
            NSBezierPath(roundedRect: NSRect(x: 312, y: y - 14, width: 400, height: 50), xRadius: 12, yRadius: 12).fill()
        }
        if w > 0 {
            c(0x8C96AB).setFill()
            NSBezierPath(roundedRect: NSRect(x: 332, y: y, width: w, height: 22), xRadius: 11, yRadius: 11).fill()
        } else {
            c(0x0E8FB3).setFill()
            NSBezierPath(roundedRect: NSRect(x: 352, y: y - 2, width: 190, height: 28), xRadius: 14, yRadius: 14).fill()
        }
        y -= 62
    }

    // Bookmark ribbon hanging over the top edge
    let rib = NSBezierPath()
    rib.move(to: NSPoint(x: 628, y: 846))
    rib.line(to: NSPoint(x: 704, y: 846))
    rib.line(to: NSPoint(x: 704, y: 706))
    rib.line(to: NSPoint(x: 666, y: 742))
    rib.line(to: NSPoint(x: 628, y: 706))
    rib.close()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 12, color: c(0x000000, 0.35).cgColor)
    c(0xF5921E).setFill()
    rib.fill()
    ctx.restoreGState()
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
                   ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
                   ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}
