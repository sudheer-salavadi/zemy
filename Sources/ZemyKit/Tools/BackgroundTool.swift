import SwiftUI
import Vision
import CoreImage

struct CutoutOptions: Equatable {
    enum Fill: String, CaseIterable, Identifiable {
        case transparent = "None", color = "Color", blur = "Blur"
        var id: Self { self }
    }
    var fill: Fill = .transparent
    var fillColor: Color = .white
    var blur = 30.0
    var feather = 0.0
    var outline = 0.0
    var outlineColor: Color = .white
    var shadow = 0.0
    var crop = false
    var invert = false
}

@MainActor @Observable
final class BackgroundModel {
    var sourceID: UUID?
    var original: CIImage?
    var mask: CIImage?
    var subject: CGRect = .zero
    var result: CGImage?
    var busy = false
    var failed = false
    var options = CutoutOptions() { didSet { if options != oldValue { compose() } } }

    func load(_ w: WorkImage) async {
        guard sourceID != w.id else { return }
        sourceID = w.id
        busy = true; failed = false; result = nil
        let cg = w.image
        let found = await Task.detached { Self.foreground(cg) }.value
        guard sourceID == w.id else { return }
        busy = false
        original = CIImage(cgImage: cg)
        guard let found else { failed = true; mask = nil; return }
        (mask, subject) = found
        compose()
    }

    /// Vision subject mask at full resolution + subject bounds (Core Image coordinates).
    nonisolated static func foreground(_ cg: CGImage) -> (CIImage, CGRect)? {
        let req = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg)
        guard (try? handler.perform([req])) != nil, let obs = req.results?.first,
              let buf = try? obs.generateScaledMaskForImage(forInstances: obs.allInstances, from: handler) else { return nil }
        CVPixelBufferLockBaseAddress(buf, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buf, .readOnly) }
        let w = CVPixelBufferGetWidth(buf), h = CVPixelBufferGetHeight(buf), row = CVPixelBufferGetBytesPerRow(buf)
        let base = CVPixelBufferGetBaseAddress(buf)!
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let p = (base + y * row).assumingMemoryBound(to: Float32.self)
            for x in 0..<w where p[x] > 0.5 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        let rect = maxX < 0 ? CGRect(x: 0, y: 0, width: w, height: h)
            : CGRect(x: minX, y: h - maxY - 1, width: maxX - minX + 1, height: maxY - minY + 1)
        return (CIImage(cvPixelBuffer: buf), rect)
    }

    func compose() {
        guard let img = original, var m = mask else { return }
        let o = options, ext = img.extent
        if o.invert { m = m.applyingFilter("CIColorInvert") }
        if o.feather > 0 { m = m.clampedToExtent().applyingGaussianBlur(sigma: o.feather).cropped(to: ext) }
        func solid(_ c: CIColor) -> CIImage { CIImage(color: c).cropped(to: ext) }
        func masked(_ i: CIImage, _ mask: CIImage) -> CIImage {
            i.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: mask])
        }
        var canvas: CIImage = switch o.fill {
        case .transparent: CIImage.empty()
        case .color: solid(o.fillColor.ci)
        case .blur: img.clampedToExtent().applyingGaussianBlur(sigma: o.blur).cropped(to: ext)
        }
        if o.shadow > 0 {
            let shadow = masked(solid(CIColor(red: 0, green: 0, blue: 0, alpha: 0.55)), m)
                .applyingGaussianBlur(sigma: o.shadow)
                .transformed(by: CGAffineTransform(translationX: 0, y: -o.shadow * 0.6))
            canvas = shadow.composited(over: canvas)
        }
        if o.outline > 0 {
            let grown = m.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: o.outline])
            canvas = masked(solid(o.outlineColor.ci), grown).composited(over: canvas)
        }
        let out = masked(img, m).composited(over: canvas)
        let pad = o.outline + o.shadow * 2 + 12
        let rect = o.crop && !o.invert ? subject.insetBy(dx: -pad, dy: -pad).intersection(ext).integral : ext
        result = ciContext.createCGImage(out, from: rect, format: .RGBA8, colorSpace: sRGB)
    }
}

struct BackgroundToolView: View {
    @Bindable var model: BackgroundModel
    @Environment(AppState.self) private var state

    var body: some View {
        SingleImageTool(tool: .background) { cur in
            ZStack {
                CompareView(before: cur.image, after: model.result, labels: ("Original", "Cutout"))
                if model.busy {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Finding the subject…").font(.callout)
                    }
                    .padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .task(id: cur.id) { await model.load(cur) }
        } inspector: {
            if model.failed {
                Label("No clear subject found in this image.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            Panel(title: "Background", symbol: "square.3.layers.3d") {
                Picker("Fill", selection: $model.options.fill) {
                    ForEach(CutoutOptions.Fill.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if model.options.fill == .color { ColorPicker("Color", selection: $model.options.fillColor) }
                if model.options.fill == .blur { SliderRow(label: "Blur", value: $model.options.blur, range: 2...120) }
                Toggle("Keep background, remove subject", isOn: $model.options.invert)
            }
            Panel(title: "Edges & Effects", symbol: "wand.and.stars") {
                SliderRow(label: "Feather", value: $model.options.feather, range: 0...20) { "\(Int($0)) px" }
                SliderRow(label: "Sticker outline", value: $model.options.outline, range: 0...60) { "\(Int($0)) px" }
                if model.options.outline > 0 { ColorPicker("Outline color", selection: $model.options.outlineColor) }
                SliderRow(label: "Drop shadow", value: $model.options.shadow, range: 0...60) { "\(Int($0)) px" }
                Toggle("Crop to subject", isOn: $model.options.crop)
            }
            if let name = state.current?.name {
                ExportPanel(id: "bg", name: "\(name)-cutout", formats: [.png, .webp, .heic, .avif, .tiff, .jpeg]) { _ in model.result }
            }
            Label("Runs on-device with the Neural Engine. Nothing leaves your Mac.", systemImage: "cpu")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
