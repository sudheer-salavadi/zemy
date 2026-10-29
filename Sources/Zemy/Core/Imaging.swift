import AppKit
import Accelerate
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import CWebP
import zlib

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
/// Metal-backed Core Image context shared by every tool.
let ciContext = CIContext(options: [.workingColorSpace: sRGB, .cacheIntermediates: false])

// MARK: - Formats

enum ImageFormat: String, CaseIterable, Identifiable, Codable {
    case png, jpeg, webp, heic, avif, gif, tiff, bmp, jp2, ico, icns, pdf, psd, tga

    var id: Self { self }
    var label: String {
        switch self {
        case .jpeg: "JPEG"
        case .jp2: "JPEG 2000"
        default: rawValue.uppercased()
        }
    }
    var ext: String { self == .jpeg ? "jpg" : rawValue }
    var uti: String {
        switch self {
        case .png: UTType.png.identifier
        case .jpeg: UTType.jpeg.identifier
        case .webp: UTType.webP.identifier
        case .heic: UTType.heic.identifier
        case .avif: "public.avif"
        case .gif: UTType.gif.identifier
        case .tiff: UTType.tiff.identifier
        case .bmp: UTType.bmp.identifier
        case .jp2: "public.jpeg-2000"
        case .ico: UTType.ico.identifier
        case .icns: UTType.icns.identifier
        case .pdf: UTType.pdf.identifier
        case .psd: "com.adobe.photoshop-image"
        case .tga: "com.truevision.tga-image"
        }
    }
    /// Formats where a quality slider is meaningful.
    var isLossy: Bool { [.jpeg, .webp, .heic, .avif, .jp2].contains(self) }
    var hasAlpha: Bool { ![.jpeg, .bmp].contains(self) }
    /// "Visually lossless" defaults, roughly what TinyPNG / Squoosh land on.
    var smartQuality: Double {
        switch self {
        case .jpeg: 0.78
        case .webp: 0.80
        case .heic, .jp2: 0.65
        case .avif: 0.60
        default: 1
        }
    }
    var blurb: String {
        switch self {
        case .png: "Lossless · alpha"
        case .jpeg: "Photos · universal"
        case .webp: "Web · alpha"
        case .heic: "Apple · tiny"
        case .avif: "Next-gen web"
        case .gif: "256 colors · anim"
        case .tiff: "Print · lossless"
        case .pdf: "Vector container"
        case .ico: "Windows icon"
        case .icns: "macOS icon"
        default: label
        }
    }

    init?(uti: String) {
        guard let f = Self.allCases.first(where: { $0.uti == uti }) else { return nil }
        self = f
    }

    static let common: [ImageFormat] = [.png, .jpeg, .webp, .heic, .avif, .gif, .tiff, .pdf]
}

// MARK: - Loading

struct LoadedImage {
    var image: CGImage
    var format: ImageFormat?
    var frames: [(image: CGImage, delay: Double)] = []
    var isAnimated: Bool { frames.count > 1 }
}

enum ImageIOKit {
    static func load(_ data: Data) -> LoadedImage? {
        if let src = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(src) > 0,
           let image = orientedImage(src, 0) {
            let format = (CGImageSourceGetType(src) as String?).flatMap(ImageFormat.init(uti:))
            var loaded = LoadedImage(image: image, format: format)
            let count = CGImageSourceGetCount(src)
            if count > 1, format != .pdf, format != .ico, format != .icns, format != .tiff {
                loaded.frames = (0..<count).compactMap { i in
                    CGImageSourceCreateImageAtIndex(src, i, nil).map { ($0, frameDelay(src, i)) }
                }
            }
            return loaded
        }
        // NSImage also understands SVG, EPS and friends.
        guard let ns = NSImage(data: data) else { return nil }
        var rect = CGRect(origin: .zero, size: ns.size)
        return ns.cgImage(forProposedRect: &rect, context: nil, hints: nil).map { LoadedImage(image: $0) }
    }

    /// Full-resolution decode with EXIF orientation applied.
    static func orientedImage(_ src: CGImageSource, _ i: Int) -> CGImage? {
        let p = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any] ?? [:]
        let side = max(p[kCGImagePropertyPixelWidth] as? Int ?? 0, p[kCGImagePropertyPixelHeight] as? Int ?? 0)
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(side, 1),
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, i, opts as CFDictionary) ?? CGImageSourceCreateImageAtIndex(src, i, nil)
    }

    private static func frameDelay(_ src: CGImageSource, _ i: Int) -> Double {
        let p = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any] ?? [:]
        let dicts: [(CFString, CFString, CFString)] = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
        ]
        for (dict, unclamped, clamped) in dicts {
            if let d = p[dict] as? [CFString: Any], let t = (d[unclamped] as? Double) ?? (d[clamped] as? Double), t > 0 { return t }
        }
        return 0.1
    }

    /// Writes one or more images (frames, icon sizes) with ImageIO.
    static func write(_ images: [CGImage], type: String, file: [CFString: Any] = [:],
                      frame: (Int) -> [CFString: Any] = { _ in [:] }) -> Data? {
        let data = NSMutableData()
        guard !images.isEmpty, let dst = CGImageDestinationCreateWithData(data, type as CFString, images.count, nil) else { return nil }
        CGImageDestinationSetProperties(dst, file as CFDictionary)
        for (i, img) in images.enumerated() { CGImageDestinationAddImage(dst, img, frame(i) as CFDictionary) }
        return CGImageDestinationFinalize(dst) ? data as Data : nil
    }
}

// MARK: - Pixels

/// Straight (un-premultiplied) sRGB RGBA8 pixels.
struct RGBA {
    let width: Int, height: Int
    var data: [UInt8]

    var isOpaque: Bool {
        data.withUnsafeBufferPointer { p in
            stride(from: 3, to: p.count, by: 4).allSatisfy { p[$0] == 255 }
        }
    }

    func cgImage() -> CGImage? {
        guard let provider = CGDataProvider(data: Data(data) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: sRGB, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    subscript(x: Int, y: Int) -> SIMD4<UInt8> {
        let i = (y * width + x) * 4
        return SIMD4(data[i], data[i + 1], data[i + 2], data[i + 3])
    }
}

extension CGImage {
    var size: CGSize { CGSize(width: width, height: height) }

    static func draw(_ w: Int, _ h: Int, opaque: Bool = false, _ body: (CGContext) -> Void) -> CGImage? {
        let info = opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: sRGB, bitmapInfo: info.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        body(ctx)
        return ctx.makeImage()
    }

    func rgba() -> RGBA {
        var buf = [UInt8](repeating: 0, count: width * height * 4)
        buf.withUnsafeMutableBytes { p in
            guard let ctx = CGContext(data: p.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: sRGB,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.draw(self, in: CGRect(origin: .zero, size: size))
            var v = vImage_Buffer(data: p.baseAddress, height: vImagePixelCount(height),
                                  width: vImagePixelCount(width), rowBytes: width * 4)
            vImageUnpremultiplyData_RGBA8888(&v, &v, vImage_Flags(kvImageNoFlags))
        }
        return RGBA(width: width, height: height, data: buf)
    }

    /// GPU Lanczos resample.
    func resized(to target: CGSize) -> CGImage {
        let w = max(1, Int(target.width.rounded())), h = max(1, Int(target.height.rounded()))
        guard w != width || h != height else { return self }
        let sx = CGFloat(w) / CGFloat(width), sy = CGFloat(h) / CGFloat(height)
        let ci = CIImage(cgImage: self).clampedToExtent()
            .applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: sy, kCIInputAspectRatioKey: sx / sy])
        return ciContext.createCGImage(ci, from: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBA8, colorSpace: sRGB) ?? self
    }

    func fitted(maxSide: CGFloat) -> CGImage {
        let k = maxSide / CGFloat(max(width, height))
        return k < 1 ? resized(to: CGSize(width: CGFloat(width) * k, height: CGFloat(height) * k)) : self
    }

    func flattened(_ color: CGColor = .white) -> CGImage {
        CGImage.draw(width, height, opaque: true) { ctx in
            ctx.setFillColor(color)
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.draw(self, in: CGRect(origin: .zero, size: size))
        } ?? self
    }

    var pngData: Data? { ImageIOKit.write([self], type: UTType.png.identifier) }
}

// MARK: - Resize spec

enum ResizeMode: String, CaseIterable, Identifiable {
    case none = "Off", width = "Width", height = "Height", fit = "Fit", exact = "Exact", percent = "%"
    var id: Self { self }
}

struct ResizeSpec: Equatable {
    var mode: ResizeMode = .none
    var width: Double = 1080
    var height: Double = 1080
    var percent: Double = 50
    var allowUpscale = false

    func target(for s: CGSize) -> CGSize? {
        let t: CGSize
        switch mode {
        case .none: return nil
        case .width: t = CGSize(width: width, height: s.height * width / s.width)
        case .height: t = CGSize(width: s.width * height / s.height, height: height)
        case .fit:
            let k = min(width / s.width, height / s.height)
            t = CGSize(width: s.width * k, height: s.height * k)
        case .exact: t = CGSize(width: width, height: height)
        case .percent: t = CGSize(width: s.width * percent / 100, height: s.height * percent / 100)
        }
        let r = CGSize(width: max(1, t.width.rounded()), height: max(1, t.height.rounded()))
        if mode != .exact, !allowUpscale, r.width > s.width || r.height > s.height { return nil }
        return r == s ? nil : r
    }
}

// MARK: - Encoding

struct EncodeOptions: Equatable {
    var format: ImageFormat
    var quality: Double = 0.85
    var lossless = false
    /// PNG palette size; 0 keeps full colour (lossless).
    var pngColors = 0
    var dither = true
}

enum Encoder {
    static func encode(_ img: CGImage, _ o: EncodeOptions) -> Data? {
        switch o.format {
        case .png: return PNG.encode(img, colors: o.pngColors, dither: o.dither)
        case .webp: return webp(img, quality: o.quality, lossless: o.lossless)
        case .ico: return ImageIOKit.write([img.fitted(maxSide: 256)], type: o.format.uti)
        case .icns:
            let side = min(1024, max(img.width, img.height))
            let sizes = [16, 32, 64, 128, 256, 512, 1024].filter { $0 <= side }
            return ImageIOKit.write(sizes.map { img.resized(to: CGSize(width: $0, height: $0)) }, type: o.format.uti)
        default:
            let image = o.format.hasAlpha ? img : img.flattened()
            let props: [CFString: Any] = o.format.isLossy
                ? [kCGImageDestinationLossyCompressionQuality: o.lossless ? 1.0 : o.quality] : [:]
            return ImageIOKit.write([image], type: o.format.uti, frame: { _ in props })
        }
    }

    static func animatedGIF(_ frames: [(image: CGImage, delay: Double)]) -> Data? {
        ImageIOKit.write(frames.map(\.image), type: UTType.gif.identifier,
                         file: [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]],
                         frame: { [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: frames[$0].delay]] })
    }

    static func webp(_ img: CGImage, quality: Double, lossless: Bool) -> Data? {
        let px = img.rgba()
        var config = WebPConfig()
        guard WebPConfigInit(&config) != 0 else { return nil }
        config.lossless = lossless ? 1 : 0
        config.quality = lossless ? 90 : Float(quality * 100)
        config.method = 5
        config.use_sharp_yuv = 1
        var pic = WebPPicture()
        guard WebPPictureInit(&pic) != 0 else { return nil }
        pic.use_argb = lossless ? 1 : 0
        pic.width = Int32(px.width)
        pic.height = Int32(px.height)
        let writer = UnsafeMutablePointer<WebPMemoryWriter>.allocate(capacity: 1)
        defer { WebPMemoryWriterClear(writer); writer.deallocate(); WebPPictureFree(&pic) }
        WebPMemoryWriterInit(writer)
        pic.writer = WebPMemoryWrite
        pic.custom_ptr = UnsafeMutableRawPointer(writer)
        let ok = px.data.withUnsafeBufferPointer { WebPPictureImportRGBA(&pic, $0.baseAddress, Int32(px.width * 4)) != 0 }
        guard ok, WebPEncode(&config, &pic) != 0 else { return nil }
        return Data(bytes: writer.pointee.mem, count: writer.pointee.size)
    }
}

// MARK: - Colour quantisation (median cut + k-means refine + Floyd–Steinberg)

struct Indexed {
    let width: Int, height: Int
    var indices: [UInt8]
    var palette: [SIMD4<UInt8>]
}

enum Quantizer {
    struct Entry { var c: SIMD4<Float>; var n: Float }
    private static let weights = SIMD4<Float>(0.299, 0.587, 0.114, 1)

    @inline(__always) static func dist(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> Float {
        let d = a - b
        return (d * d * weights).sum()
    }

    @inline(__always) static func key(_ c: SIMD4<Float>) -> Int {
        let q = SIMD4<Int32>(c, rounding: .down) &>> 3
        return Int(q.x) << 15 | Int(q.y) << 10 | Int(q.z) << 5 | Int(q.w)
    }

    /// 5-bit-per-channel histogram of visible pixels (bucket means).
    static func histogram(_ px: RGBA) -> [Entry] {
        var slot = [Int32](repeating: -1, count: 1 << 20)
        var entries: [Entry] = []
        px.data.withUnsafeBufferPointer { p in
            for i in stride(from: 0, to: p.count, by: 4) where p[i + 3] > 0 {
                let c = SIMD4<Float>(Float(p[i]), Float(p[i + 1]), Float(p[i + 2]), Float(p[i + 3]))
                let k = key(c)
                if slot[k] < 0 { slot[k] = Int32(entries.count); entries.append(Entry(c: .zero, n: 0)) }
                let e = Int(slot[k])
                entries[e].c += c
                entries[e].n += 1
            }
        }
        return entries.map { Entry(c: $0.c / $0.n, n: $0.n) }
    }

    static func medianCut(_ entries: [Entry], _ k: Int) -> [Entry] {
        var boxes: [[Entry]] = [entries]
        while boxes.count < k {
            var best = -1, bestScore: Float = 0, bestAxis = 0
            for (i, box) in boxes.enumerated() where box.count > 1 {
                var lo = SIMD4<Float>(repeating: .greatestFiniteMagnitude), hi = -lo, pop: Float = 0
                for e in box { lo = pointwiseMin(lo, e.c); hi = pointwiseMax(hi, e.c); pop += e.n }
                let range = (hi - lo) * weights
                let axis = (0..<4).max { range[$0] < range[$1] }!
                let score = range[axis] * pop.squareRoot()
                if score > bestScore { best = i; bestScore = score; bestAxis = axis }
            }
            guard best >= 0 else { break }
            let box = boxes[best].sorted { $0.c[bestAxis] < $1.c[bestAxis] }
            let half = box.reduce(0) { $0 + $1.n } / 2
            var acc: Float = 0, cut = 1
            for (j, e) in box.enumerated() { acc += e.n; if acc >= half { cut = j + 1; break } }
            cut = min(max(cut, 1), box.count - 1)
            boxes[best] = Array(box[..<cut])
            boxes.append(Array(box[cut...]))
        }
        return boxes.map { box in
            let n = box.reduce(0) { $0 + $1.n }
            return Entry(c: box.reduce(.zero) { $0 + $1.c * $1.n } / n, n: n)
        }
    }

    static func nearest(_ c: SIMD4<Float>, _ pal: [Entry]) -> Int {
        var best = 0, bd = Float.greatestFiniteMagnitude
        for (j, p) in pal.enumerated() { let d = dist(c, p.c); if d < bd { bd = d; best = j } }
        return best
    }

    static func refine(_ pal: inout [Entry], _ entries: [Entry], iterations: Int = 4) {
        for _ in 0..<iterations {
            var acc = [Entry](repeating: Entry(c: .zero, n: 0), count: pal.count)
            for e in entries {
                let j = nearest(e.c, pal)
                acc[j].c += e.c * e.n
                acc[j].n += e.n
            }
            for j in pal.indices where acc[j].n > 0 { pal[j] = Entry(c: acc[j].c / acc[j].n, n: acc[j].n) }
        }
    }

    /// Dominant colours, most common first.
    static func palette(_ px: RGBA, colors: Int) -> [Entry] {
        let hist = histogram(px)
        guard !hist.isEmpty else { return [] }
        var pal = hist.count <= colors ? hist : medianCut(hist, colors)
        refine(&pal, hist)
        return pal.sorted { $0.n > $1.n }
    }

    static func quantize(_ px: RGBA, colors: Int, dither: Bool) -> Indexed {
        let hasClear = px.data.withUnsafeBufferPointer { p in stride(from: 3, to: p.count, by: 4).contains { p[$0] == 0 } }
        var pal = palette(px, colors: max(1, colors - (hasClear ? 1 : 0)))
        if hasClear { pal.append(Entry(c: .zero, n: 0)) }
        let clear = pal.count - 1
        pal = pal.map { Entry(c: $0.c.rounded(.toNearestOrEven), n: $0.n) }
        let w = px.width, h = px.height
        let search = hasClear ? Array(pal.dropLast()) : pal
        var lut = [Int16](repeating: -1, count: 1 << 20)
        var out = [UInt8](repeating: 0, count: w * h)
        var cur = [SIMD4<Float>](repeating: .zero, count: w + 2), next = cur
        let strength: Float = dither ? 0.85 / 16 : 0
        px.data.withUnsafeBufferPointer { p in
            for y in 0..<h {
                for x in 0..<w {
                    let i = (y * w + x) * 4
                    if hasClear && p[i + 3] == 0 { out[y * w + x] = UInt8(clear); continue }
                    let src = SIMD4<Float>(Float(p[i]), Float(p[i + 1]), Float(p[i + 2]), Float(p[i + 3]))
                    let c = (src + cur[x + 1]).clamped(lowerBound: .zero, upperBound: SIMD4(repeating: 255))
                    let k = key(c)
                    if lut[k] < 0 { lut[k] = Int16(nearest(c, search)) }
                    let j = Int(lut[k])
                    out[y * w + x] = UInt8(j)
                    if dither {
                        let e = (c - pal[j].c) * strength
                        cur[x + 2] += e * 7; next[x] += e * 3; next[x + 1] += e * 5; next[x + 2] += e
                    }
                }
                if dither { swap(&cur, &next); for i in next.indices { next[i] = .zero } }
            }
        }
        return Indexed(width: w, height: h, indices: out, palette: pal.map { SIMD4<UInt8>(clamping: SIMD4<Int32>($0.c, rounding: .toNearestOrEven)) })
    }

    /// Lossless palette when the image already has ≤ 256 distinct colours.
    static func exact(_ px: RGBA) -> Indexed? {
        var map: [UInt32: UInt8] = [:]
        var pal: [UInt32] = []
        var out = [UInt8](repeating: 0, count: px.width * px.height)
        let ok = px.data.withUnsafeBytes { raw -> Bool in
            let p = raw.bindMemory(to: UInt32.self)
            var last: UInt32 = 0xFFFF_FFFF, lastIdx: UInt8 = 0
            for i in 0..<p.count {
                var v = p[i]
                if v >> 24 == 0 { v = 0 } // alpha is the high byte on little-endian
                if v == last { out[i] = lastIdx; continue }
                if let j = map[v] { out[i] = j; last = v; lastIdx = j; continue }
                guard pal.count < 256 else { return false }
                let j = UInt8(pal.count)
                map[v] = j; pal.append(v); out[i] = j; last = v; lastIdx = j
            }
            return true
        }
        guard ok else { return nil }
        let palette = pal.map { v in SIMD4<UInt8>(UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 24)) }
        return Indexed(width: px.width, height: px.height, indices: out, palette: palette)
    }
}

// MARK: - PNG writer (palette + adaptive filters + zlib level 9)

enum PNG {
    static func encode(_ img: CGImage, colors: Int = 0, dither: Bool = true) -> Data? {
        let px = img.rgba()
        if colors > 0 { return indexed(Quantizer.quantize(px, colors: colors, dither: dither)) }
        let mine = Quantizer.exact(px).map(indexed) ?? truecolor(px)
        let system = img.pngData
        return [mine, system].compactMap { $0 }.min { $0.count < $1.count }
    }

    static func indexed(_ q: Indexed) -> Data {
        // Translucent entries first so tRNS can stop early.
        let order = q.palette.indices.filter { q.palette[$0].w < 255 } + q.palette.indices.filter { q.palette[$0].w == 255 }
        var remap = [UInt8](repeating: 0, count: 256)
        for (new, old) in order.enumerated() { remap[old] = UInt8(new) }
        let pal = order.map { q.palette[$0] }
        let n = pal.count
        let depth = n <= 2 ? 1 : n <= 4 ? 2 : n <= 16 ? 4 : 8
        let rowBytes = (q.width * depth + 7) / 8
        var raw = [UInt8](repeating: 0, count: (rowBytes + 1) * q.height)
        for y in 0..<q.height {
            let row = y * (rowBytes + 1) + 1
            for x in 0..<q.width {
                let bit = x * depth
                raw[row + bit / 8] |= remap[Int(q.indices[y * q.width + x])] << (8 - depth - bit % 8)
            }
        }
        let translucent = pal.prefix(while: { $0.w < 255 }).map(\.w)
        var png = signature
        png += chunk("IHDR", be32(q.width) + be32(q.height) + [UInt8(depth), 3, 0, 0, 0])
        png += chunk("PLTE", pal.flatMap { [$0.x, $0.y, $0.z] })
        if !translucent.isEmpty { png += chunk("tRNS", Array(translucent)) }
        png += chunk("IDAT", zcompress(raw))
        png += chunk("IEND", [])
        return png
    }

    static func truecolor(_ px: RGBA) -> Data {
        let alpha = !px.isOpaque, bpp = alpha ? 4 : 3
        let raw = alpha ? px.data : px.data.enumerated().compactMap { $0.offset % 4 == 3 ? nil : $0.element }
        var png = signature
        png += chunk("IHDR", be32(px.width) + be32(px.height) + [8, alpha ? 6 : 2, 0, 0, 0])
        png += chunk("IDAT", zcompress(filter(raw, rowBytes: px.width * bpp, height: px.height, bpp: bpp)))
        png += chunk("IEND", [])
        return png
    }

    /// Per-row adaptive filter choice (minimum sum of absolute differences).
    static func filter(_ raw: [UInt8], rowBytes: Int, height: Int, bpp: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: (rowBytes + 1) * height)
        var cand = [UInt8](repeating: 0, count: rowBytes * 5)
        let zero = [UInt8](repeating: 0, count: rowBytes)
        raw.withUnsafeBufferPointer { r in
            zero.withUnsafeBufferPointer { z in
                for y in 0..<height {
                    let row = r.baseAddress! + y * rowBytes
                    let prev = y > 0 ? r.baseAddress! + (y - 1) * rowBytes : z.baseAddress!
                    var best = 0, bestSum = Int.max
                    for f in 0..<5 {
                        var sum = 0
                        for i in 0..<rowBytes {
                            let x = Int(row[i]), b = Int(prev[i])
                            let a = i >= bpp ? Int(row[i - bpp]) : 0, c = i >= bpp ? Int(prev[i - bpp]) : 0
                            let pred: Int
                            switch f {
                            case 0: pred = 0
                            case 1: pred = a
                            case 2: pred = b
                            case 3: pred = (a + b) >> 1
                            default:
                                let p = a + b - c, pa = abs(p - a), pb = abs(p - b), pc = abs(p - c)
                                pred = pa <= pb && pa <= pc ? a : pb <= pc ? b : c
                            }
                            let v = UInt8(truncatingIfNeeded: x - pred)
                            cand[f * rowBytes + i] = v
                            sum += Int(Int8(bitPattern: v).magnitude)
                        }
                        if sum < bestSum { bestSum = sum; best = f }
                    }
                    let o = y * (rowBytes + 1)
                    out[o] = UInt8(best)
                    out.replaceSubrange(o + 1..<o + 1 + rowBytes, with: cand[best * rowBytes..<(best + 1) * rowBytes])
                }
            }
        }
        return out
    }

    static func zcompress(_ input: [UInt8]) -> [UInt8] {
        let strategies = input.count < 8_000_000 ? [Z_DEFAULT_STRATEGY, Z_FILTERED] : [Z_DEFAULT_STRATEGY]
        var results = [[UInt8]](repeating: [], count: strategies.count)
        results.withUnsafeMutableBufferPointer { slots in
        let slots = slots // each iteration writes only its own slot
        DispatchQueue.concurrentPerform(iterations: strategies.count) { n in
            let strategy = strategies[n]
            var s = z_stream()
            deflateInit2_(&s, 9, Z_DEFLATED, 15, 9, strategy, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
            defer { deflateEnd(&s) }
            var out = [UInt8](repeating: 0, count: Int(deflateBound(&s, UInt(input.count))))
            input.withUnsafeBufferPointer { i in
                out.withUnsafeMutableBufferPointer { o in
                    s.next_in = UnsafeMutablePointer(mutating: i.baseAddress)
                    s.avail_in = UInt32(i.count)
                    s.next_out = o.baseAddress
                    s.avail_out = UInt32(o.count)
                    deflate(&s, Z_FINISH)
                }
            }
            slots[n] = Array(out.prefix(Int(s.total_out)))
        }
        }
        return results.min { $0.count < $1.count }!
    }

    private static let signature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    private static func be32<T: BinaryInteger>(_ v: T) -> [UInt8] { withUnsafeBytes(of: UInt32(v).bigEndian, Array.init) }
    private static func chunk(_ type: String, _ body: [UInt8]) -> Data {
        let t = Array(type.utf8)
        let crc = crc32(crc32(0, t, 4), body, UInt32(body.count))
        return Data(be32(body.count) + t + body + be32(crc))
    }
}
