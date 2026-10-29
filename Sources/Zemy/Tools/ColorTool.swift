import SwiftUI

// MARK: - Colour math

struct RGB: Hashable {
    var r, g, b: Double
    var a = 1.0

    static let white = RGB(r: 1, g: 1, b: 1), black = RGB(r: 0, g: 0, b: 0)

    init(r: Double, g: Double, b: Double, a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    init(_ ns: NSColor) {
        let c = ns.usingColorSpace(.sRGB) ?? .black
        self.init(r: c.redComponent, g: c.greenComponent, b: c.blueComponent, a: c.alphaComponent)
    }
    init(_ p: SIMD4<UInt8>) { self.init(r: Double(p.x) / 255, g: Double(p.y) / 255, b: Double(p.z) / 255, a: Double(p.w) / 255) }
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let n = s.count == 8 ? v >> 8 : v
        self.init(r: Double(n >> 16 & 0xFF) / 255, g: Double(n >> 8 & 0xFF) / 255, b: Double(n & 0xFF) / 255,
                  a: s.count == 8 ? Double(v & 0xFF) / 255 : 1)
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    private var bytes: (Int, Int, Int) { (Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded())) }

    var hex: String {
        let (R, G, B) = bytes
        return String(format: "#%02X%02X%02X", R, G, B) + (a < 1 ? String(format: "%02X", Int(a * 255)) : "")
    }
    var rgbString: String { let (R, G, B) = bytes; return a < 1 ? "rgba(\(R), \(G), \(B), \(String(format: "%.2f", a)))" : "rgb(\(R), \(G), \(B))" }

    var hsb: (h: Double, s: Double, b: Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d > 0 {
            h = mx == r ? (g - b) / d : mx == g ? 2 + (b - r) / d : 4 + (r - g) / d
            h = (h * 60 + 360).truncatingRemainder(dividingBy: 360)
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }
    var hslString: String {
        let mx = max(r, g, b), mn = min(r, g, b), l = (mx + mn) / 2, d = mx - mn
        let s = d == 0 ? 0 : d / (1 - abs(2 * l - 1))
        return "hsl(\(Int(hsb.h.rounded())), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%)"
    }
    var hsbString: String { let v = hsb; return "hsb(\(Int(v.h.rounded())), \(Int((v.s * 100).rounded()))%, \(Int((v.b * 100).rounded()))%)" }
    var cmykString: String {
        let k = 1 - max(r, g, b)
        guard k < 1 else { return "cmyk(0%, 0%, 0%, 100%)" }
        let f = { (v: Double) in Int(((1 - v - k) / (1 - k) * 100).rounded()) }
        return "cmyk(\(f(r))%, \(f(g))%, \(f(b))%, \(Int((k * 100).rounded()))%)"
    }
    var oklchString: String {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let (R, G, B) = (lin(r), lin(g), lin(b))
        let l = cbrt(0.4122214708 * R + 0.5363325363 * G + 0.0514459929 * B)
        let m = cbrt(0.2119034982 * R + 0.6806995451 * G + 0.1073969566 * B)
        let s = cbrt(0.0883024619 * R + 0.2817188376 * G + 0.6299787005 * B)
        let L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let Bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        let h = (atan2(Bb, A) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        return String(format: "oklch(%.1f%% %.3f %.1f)", L * 100, hypot(A, Bb), h)
    }
    var swiftUI: String { String(format: "Color(red: %.3f, green: %.3f, blue: %.3f)", r, g, b) }
    var android: String { let (R, G, B) = bytes; return String(format: "0xFF%02X%02X%02X", R, G, B) }

    var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
    func contrast(_ o: RGB) -> Double {
        let (a, b) = (luminance, o.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
    func mixed(_ o: RGB, _ t: Double) -> RGB { RGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t) }

    /// Tailwind-style 50…900 scale around this colour.
    var scale: [(String, RGB)] {
        let steps: [(String, RGB, Double)] = [("50", .white, 0.92), ("100", .white, 0.8), ("200", .white, 0.6), ("300", .white, 0.4),
                                              ("400", .white, 0.2), ("500", .white, 0), ("600", .black, 0.15), ("700", .black, 0.32),
                                              ("800", .black, 0.5), ("900", .black, 0.68)]
        return steps.map { ($0.0, mixed($0.1, $0.2)) }
    }

    var formats: [(String, String)] {
        [("HEX", hex), ("RGB", rgbString), ("HSL", hslString), ("HSB", hsbString), ("CMYK", cmykString),
         ("OKLCH", oklchString), ("SwiftUI", swiftUI), ("Android", android)]
    }
}

// MARK: - Model

@MainActor @Observable
final class ColorModel {
    var sourceID: UUID?
    var pixels: RGBA?
    var palette: [RGB] = []
    var current = RGB(r: 0.35, g: 0.34, b: 0.84)
    var against = RGB.white
    var history: [RGB] = []
    var hover: (x: Int, y: Int)?
    /// Cursor position in canvas coordinates, used to place the loupe.
    var cursor: CGPoint = .zero

    func load(_ w: WorkImage) async {
        guard sourceID != w.id else { return }
        sourceID = w.id
        let cg = w.image
        let (px, pal) = await Task.detached {
            let px = cg.rgba()
            let pal = Quantizer.palette(cg.fitted(maxSide: 200).rgba(), colors: 8).map { RGB(SIMD4<UInt8>(clamping: SIMD4<Int32>($0.c, rounding: .toNearestOrEven))) }
            return (px, pal)
        }.value
        pixels = px
        palette = pal
    }

    func pick(_ c: RGB) {
        current = c
        history.removeAll { $0.hex == c.hex }
        history.insert(c, at: 0)
        history = Array(history.prefix(24))
    }

    func sampleScreen() {
        NSColorSampler().show { [weak self] ns in
            guard let ns else { return }
            Task { @MainActor in self?.pick(RGB(ns)) }
        }
    }

    var paletteCSS: String {
        palette.enumerated().map { "  --color-\($0.offset + 1): \($0.element.hex);" }.joined(separator: "\n").wrappedInRoot
    }
}

private extension String { var wrappedInRoot: String { ":root {\n\(self)\n}" } }

// MARK: - View

struct ColorToolView: View {
    @Bindable var model: ColorModel
    @Environment(AppState.self) private var state

    var body: some View {
        ToolScaffold(tool: .colors) {
            if let cur = state.current { canvas(cur) }
            else {
                DropZone(tool: .colors, multiple: false, extra: AnyView(
                    Button { model.sampleScreen() } label: { Label("Pick from Screen", systemImage: "eyedropper") }
                )) { state.open($0) }
            }
        } inspector: { inspector }
        .toolbar {
            Button { model.sampleScreen() } label: { Label("Pick from Screen", systemImage: "eyedropper") }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .help("Sample any pixel on any screen (⇧⌘P)")
        }
    }

    private func canvas(_ cur: WorkImage) -> some View {
        GeometryReader { outer in
            ZoomCanvas(size: cur.image.size, checker: true) { k in
                GeometryReader { g in
                    PixelImage(image: cur.image, scale: k)
                        .onContinuousHover { phase in
                            if case .active(let p) = phase {
                                model.hover = (min(max(Int(p.x / k), 0), cur.image.width - 1), min(max(Int(p.y / k), 0), cur.image.height - 1))
                                let origin = g.frame(in: .named("colorCanvas")).origin
                                model.cursor = CGPoint(x: origin.x + p.x, y: origin.y + p.y)
                            } else { model.hover = nil }
                        }
                        .onTapGesture { p in
                            let x = min(max(Int(p.x / k), 0), cur.image.width - 1), y = min(max(Int(p.y / k), 0), cur.image.height - 1)
                            if let px = model.pixels { model.pick(RGB(px[x, y])) }
                        }
                }
            }
            .overlay(alignment: .topLeading) {
                if let h = model.hover {
                    Loupe(image: cur.image, x: h.x, y: h.y, color: model.pixels.map { RGB($0[h.x, h.y]) })
                        .position(loupeCenter(in: outer.size))
                        .allowsHitTesting(false)
                }
            }
        }
        .coordinateSpace(name: "colorCanvas")
        .onContinuousHover { if case .ended = $0 { model.hover = nil } }
        .task(id: cur.id) { await model.load(cur) }
    }

    /// Up-right of the cursor; flips left / below near the canvas edges so it never covers the sampled spot.
    private func loupeCenter(in size: CGSize) -> CGPoint {
        let w: CGFloat = 114, h: CGFloat = 140, gap: CGFloat = 22, c = model.cursor
        let x = c.x + gap + w <= size.width - 8 ? c.x + gap + w / 2 : c.x - gap - w / 2
        let y = c.y - gap - h >= 8 ? c.y - gap - h / 2 : c.y + gap + h / 2
        return CGPoint(x: min(max(x, w / 2 + 4), size.width - w / 2 - 4), y: min(max(y, h / 2 + 4), size.height - h / 2 - 4))
    }

    @ViewBuilder private var inspector: some View {
        let c = model.current
        Panel(title: "Color", symbol: "paintpalette") {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(c.color)
                .frame(height: 88)
                .overlay(alignment: .bottomLeading) {
                    Text(c.hex).font(.system(.title3, design: .monospaced).weight(.semibold))
                        .foregroundStyle(c.luminance > 0.45 ? .black : .white).padding(12)
                }
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.1)))
            HStack {
                Button { model.sampleScreen() } label: { Label("Pick from Screen", systemImage: "eyedropper") }
                Spacer()
                ColorPicker("", selection: Binding(get: { c.color }, set: { model.pick(RGB(NSColor($0))) })).labelsHidden()
            }
            VStack(spacing: 4) { ForEach(c.formats, id: \.0) { ValueRow(label: $0.0, value: $0.1) } }
        }
        Panel(title: "Tints & Shades", symbol: "square.stack.3d.down.forward") {
            HStack(spacing: 2) {
                ForEach(c.scale, id: \.0) { name, tone in
                    Button { model.current = tone } label: {
                        Rectangle().fill(tone.color).frame(height: 34)
                            .overlay(alignment: .bottom) { Text(name).font(.system(size: 8, weight: .medium)).foregroundStyle(tone.luminance > 0.45 ? .black : .white).padding(.bottom, 2) }
                    }
                    .buttonStyle(.plain).help(tone.hex)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            CopyButton(text: { c.scale.map { "  \($0.0): '\($0.1.hex)'," }.joined(separator: "\n") }, label: "Copy scale")
                .buttonStyle(.borderless).font(.caption)
        }
        Panel(title: "Contrast", symbol: "circle.lefthalf.filled") {
            ForEach([("White", RGB.white), ("Black", RGB.black), ("Custom", model.against)], id: \.0) { label, bg in
                ContrastRow(fg: c, bg: bg, label: label)
            }
            ColorPicker("Custom background", selection: Binding(get: { model.against.color }, set: { model.against = RGB(NSColor($0)) }))
        }
        if !model.palette.isEmpty {
            Panel(title: "Image Palette", symbol: "swatchpalette") {
                swatches(model.palette, height: 40)
                CopyButton(text: { model.paletteCSS }, label: "Copy as CSS variables").buttonStyle(.borderless).font(.caption)
            }
        }
        if !model.history.isEmpty {
            Panel(title: "History", symbol: "clock") { swatches(model.history, height: 22) }
        }
    }

    private func swatches(_ colors: [RGB], height: CGFloat) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
            ForEach(colors, id: \.self) { col in
                Button { model.current = col } label: {
                    RoundedRectangle(cornerRadius: 5).fill(col.color).frame(height: height)
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.primary.opacity(0.12)))
                }
                .buttonStyle(.plain).help(col.hex)
            }
        }
    }
}

private struct ContrastRow: View {
    let fg: RGB, bg: RGB, label: String
    var body: some View {
        let ratio = fg.contrast(bg)
        HStack {
            Text("Aa").font(.system(size: 17, weight: .bold)).foregroundStyle(fg.color)
                .frame(width: 44, height: 30).background(bg.color, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.1)))
            VStack(alignment: .leading, spacing: 0) {
                Text(String(format: "%.2f : 1", ratio)).font(.callout.monospacedDigit().weight(.semibold))
                Text("on \(label.lowercased())").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            badge("AA", ratio >= 4.5)
            badge("AAA", ratio >= 7)
        }
    }
    private func badge(_ t: String, _ ok: Bool) -> some View {
        Text(t).font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2)
            .background((ok ? Color.green : .red).opacity(0.18), in: Capsule())
            .foregroundStyle(ok ? .green : .red)
    }
}

/// Pixel-grid magnifier that follows the cursor.
private struct Loupe: View {
    let image: CGImage
    let x: Int, y: Int
    let color: RGB?
    private let n = 11

    var body: some View {
        VStack(spacing: 0) {
            if let crop = image.cropping(to: CGRect(x: x - n / 2, y: y - n / 2, width: n, height: n)) {
                Image(decorative: crop, scale: 1).resizable().interpolation(.none)
                    .frame(width: 110, height: 110)
                    .overlay { Rectangle().strokeBorder(.white, lineWidth: 1.5).frame(width: 10, height: 10).shadow(radius: 1) }
            }
            if let color {
                HStack(spacing: 6) {
                    Circle().fill(color.color).frame(width: 10, height: 10)
                    Text(color.hex).font(.system(size: 11, design: .monospaced).weight(.semibold))
                }
                .frame(width: 110).padding(.vertical, 5).background(.regularMaterial)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.7), lineWidth: 2))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }
}
