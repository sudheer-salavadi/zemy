// Draws Zemy's app icon (1024², macOS grid) and writes it as a PNG.
// Usage: swift Scripts/make-icon.swift out.png
import AppKit

let size = 1024.0
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    let ctx = NSGraphicsContext.current!.cgContext
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185).cgPath

    // Drop shadow under the tile
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35))
    ctx.addPath(squircle); ctx.setFillColor(rgb(0x000000)); ctx.fillPath()
    ctx.restoreGState()

    // Aurora tile: deep indigo base with teal / violet / cyan glows
    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()
    let base = CGGradient(colorsSpace: space, colors: [rgb(0x312E81), rgb(0x0B1E4A)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(base, start: CGPoint(x: 100, y: 924), end: CGPoint(x: 924, y: 100), options: [])
    for (hex, c, r) in [(UInt32(0x7C3AED), CGPoint(x: 820, y: 860), 560.0),
                        (0x14B8A6, CGPoint(x: 180, y: 160), 600.0),
                        (0x22D3EE, CGPoint(x: 860, y: 220), 420.0)] {
        let glow = CGGradient(colorsSpace: space, colors: [rgb(hex, 0.85), rgb(hex, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
    }
    // Soft top sheen
    let sheen = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.18), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
    ctx.restoreGState()

    // Bold rounded "Z"
    let font = NSFont.systemFont(ofSize: 640, weight: .black)
    let rounded = NSFont(descriptor: font.fontDescriptor.withDesign(.rounded) ?? font.fontDescriptor, size: 640) ?? font
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.shadowBlurRadius = 30
    let z = NSAttributedString(string: "Z", attributes: [.font: rounded, .foregroundColor: NSColor.white, .shadow: shadow])
    let b = z.boundingRect(with: NSSize(width: 2000, height: 2000), options: [.usesLineFragmentOrigin, .usesFontLeading])
    // Center on the glyph's cap height rather than the line box.
    let capOffset = (b.height - rounded.capHeight) / 2 + rounded.descender
    z.draw(at: CGPoint(x: (size - b.width) / 2, y: (size - b.height) / 2 + capOffset * 0.5 - 6))
    return true
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
img.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
