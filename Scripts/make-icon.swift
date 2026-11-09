// Draws Zemy's app icon (1024², macOS grid) and writes it as a PNG.
// A multitool fanned open on a cutting mat: pen nib, steel rule and CMY swatch blades.
// Usage: swift Scripts/make-icon.swift out.png
import AppKit

let size = 1024.0
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func gradient(_ stops: [(UInt32, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map { rgb($0.0, $0.1) } as CFArray, locations: nil)!
}
func pill(_ x0: CGFloat, _ x1: CGFloat, _ h: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x0, y: -h / 2, width: x1 - x0, height: h), cornerWidth: h / 2, cornerHeight: h / 2, transform: nil)
}

let pivot = CGPoint(x: 300, y: 300)
let W: CGFloat = 112

/// Runs `draw` in blade space: origin at the rivet, blade pointing along +x.
func blade(_ deg: CGFloat, in ctx: CGContext, _ draw: (CGContext) -> Void) {
    ctx.saveGState()
    ctx.translateBy(x: pivot.x, y: pivot.y)
    ctx.rotate(by: deg * .pi / 180)
    draw(ctx)
    ctx.restoreGState()
}

func shaded(_ path: CGPath, _ ctx: CGContext, fill: CGGradient) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: rgb(0x000000, 0.45))
    ctx.addPath(path); ctx.setFillColor(rgb(0x000000)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let b = path.boundingBox
    ctx.drawLinearGradient(fill, start: CGPoint(x: 0, y: b.maxY), end: CGPoint(x: 0, y: b.minY), options: [])
    ctx.restoreGState()
}

func swatch(_ deg: CGFloat, _ hi: UInt32, _ lo: UInt32, _ ctx: CGContext) {
    blade(deg, in: ctx) { c in
        let L: CGFloat = 610
        shaded(pill(-W / 2, L, W), c, fill: gradient([(hi, 1), (lo, 1)]))
        // Paper label at the tip, like a printed colour chip.
        c.saveGState()
        c.addPath(pill(-W / 2, L, W)); c.clip()
        c.setFillColor(rgb(0xFAFAF7)); c.fill(CGRect(x: L - 150, y: -W / 2, width: 150, height: W))
        c.setFillColor(rgb(0x1C1C1C, 0.75))
        c.fill(CGRect(x: L - 124, y: 6, width: 64, height: 7))
        c.fill(CGRect(x: L - 124, y: -12, width: 40, height: 5))
        c.restoreGState()
    }
}

let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    let ctx = NSGraphicsContext.current!.cgContext
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35))
    ctx.addPath(squircle); ctx.setFillColor(rgb(0x000000)); ctx.fillPath()
    ctx.restoreGState()

    // Cutting mat: green, fine grid, heavier every fourth line, 45° guide.
    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()
    ctx.drawLinearGradient(gradient([(0x177A5E, 1), (0x0C4A3A, 1)]), start: CGPoint(x: 100, y: 924), end: CGPoint(x: 924, y: 100), options: [])
    for i in stride(from: 100.0, through: 924, by: 41.2) {
        let major = Int(((i - 100) / 41.2).rounded()) % 4 == 0
        ctx.setStrokeColor(rgb(0xE8FFF4, major ? 0.17 : 0.07))
        ctx.setLineWidth(major ? 3 : 2)
        ctx.strokeLineSegments(between: [CGPoint(x: i, y: 100), CGPoint(x: i, y: 924), CGPoint(x: 100, y: i), CGPoint(x: 924, y: i)])
    }
    ctx.setStrokeColor(rgb(0xE8FFF4, 0.16)); ctx.setLineWidth(3)
    ctx.strokeLineSegments(between: [CGPoint(x: 100, y: 100), CGPoint(x: 924, y: 924)])
    ctx.drawRadialGradient(gradient([(0xFFFFFF, 0.14), (0xFFFFFF, 0)]), startCenter: CGPoint(x: 700, y: 820), startRadius: 0,
                           endCenter: CGPoint(x: 700, y: 820), endRadius: 520, options: [])

    // Back to front: nib, rule, yellow, magenta, cyan, handle.
    blade(84, in: ctx) { c in
        let L: CGFloat = 560
        let nib = CGMutablePath()
        nib.move(to: CGPoint(x: -W / 2, y: 0))
        nib.addArc(center: .zero, radius: W / 2, startAngle: .pi, endAngle: .pi * 1.5, clockwise: false)
        nib.addLine(to: CGPoint(x: L - 230, y: -W / 2))
        nib.addQuadCurve(to: CGPoint(x: L, y: 0), control: CGPoint(x: L - 70, y: -W / 2))
        nib.addQuadCurve(to: CGPoint(x: L - 230, y: W / 2), control: CGPoint(x: L - 70, y: W / 2))
        nib.addLine(to: CGPoint(x: 0, y: W / 2))
        nib.addArc(center: .zero, radius: W / 2, startAngle: .pi / 2, endAngle: .pi, clockwise: false)
        nib.closeSubpath()
        shaded(nib, c, fill: gradient([(0xF6D27A, 1), (0xC08A2E, 1), (0x8A5A16, 1)]))
        c.setFillColor(rgb(0x3A2508)); c.fillEllipse(in: CGRect(x: L - 245, y: -15, width: 30, height: 30))
        c.setStrokeColor(rgb(0x3A2508)); c.setLineWidth(5); c.setLineCap(.round)
        c.strokeLineSegments(between: [CGPoint(x: L - 215, y: 0), CGPoint(x: L - 6, y: 0)])
    }
    blade(68, in: ctx) { c in
        let L: CGFloat = 640
        let rule = CGPath(roundedRect: CGRect(x: -W / 2, y: -W / 2, width: L + W / 2, height: W), cornerWidth: 26, cornerHeight: 26, transform: nil)
        shaded(rule, c, fill: gradient([(0xF4F6F8, 1), (0xB9C0C8, 1), (0x8D96A0, 1)]))
        c.setStrokeColor(rgb(0x1E2328, 0.85)); c.setLineWidth(4)
        for (n, x) in stride(from: 90.0, through: L - 20, by: 22).enumerated() {
            let len: CGFloat = n % 5 == 0 ? 44 : 22
            c.strokeLineSegments(between: [CGPoint(x: x, y: W / 2), CGPoint(x: x, y: W / 2 - len)])
        }
    }
    swatch(52, 0xFFE14D, 0xF2B705, ctx)
    swatch(37, 0xFF4FA3, 0xD4136F, ctx)
    swatch(22, 0x3FD3FF, 0x0A94D6, ctx)

    blade(4, in: ctx) { c in
        let handle = pill(-80, 600, 160)
        shaded(handle, c, fill: gradient([(0x3A3D44, 1), (0x1B1D22, 1), (0x0E0F12, 1)]))
        c.saveGState()
        c.addPath(handle); c.clip()
        c.setStrokeColor(rgb(0xFFFFFF, 0.18)); c.setLineWidth(6)
        c.addPath(pill(-74, 594, 148)); c.strokePath()
        c.restoreGState()
        // Engraved Z near the tail.
        let font = NSFont.systemFont(ofSize: 92, weight: .heavy)
        let z = NSAttributedString(string: "ZEMY", attributes: [.font: font, .foregroundColor: NSColor(white: 1, alpha: 0.85), .kern: 14])
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
        z.draw(at: CGPoint(x: 150, y: -50))
        NSGraphicsContext.restoreGraphicsState()
    }

    // Rivet.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 8, color: rgb(0x000000, 0.6))
    ctx.setFillColor(rgb(0xC9CFD6)); ctx.fillEllipse(in: CGRect(x: pivot.x - 42, y: pivot.y - 42, width: 84, height: 84))
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: pivot.x - 42, y: pivot.y - 42, width: 84, height: 84)); ctx.clip()
    ctx.drawLinearGradient(gradient([(0xFFFFFF, 1), (0xA7AFB8, 1), (0x6B737C, 1)]), start: CGPoint(x: pivot.x - 30, y: pivot.y + 42),
                           end: CGPoint(x: pivot.x + 30, y: pivot.y - 42), options: [])
    ctx.restoreGState()
    ctx.setStrokeColor(rgb(0x4A5058, 0.7)); ctx.setLineWidth(4)
    ctx.strokeEllipse(in: CGRect(x: pivot.x - 22, y: pivot.y - 22, width: 44, height: 44))

    ctx.restoreGState()
    return true
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
img.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
