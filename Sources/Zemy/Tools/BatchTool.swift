import SwiftUI
import UniformTypeIdentifiers

// Compress & Resize and Convert are one pipeline (resize → encode) with different defaults and emphasis.

enum CompressionLevel: String, CaseIterable, Identifiable {
    case lossless = "Lossless", smart = "Smart", custom = "Custom"
    var id: Self { self }
    var note: String {
        switch self {
        case .lossless: "Pixel-identical. Re-packs and strips metadata; never grows a file."
        case .smart: "Visually lossless. Tuned quality per format, 256-color PNGs with dithering."
        case .custom: "Pick your own trade-off."
        }
    }
}

struct PipelineSettings: Equatable {
    var format: ImageFormat? = nil // nil keeps the source format
    var level: CompressionLevel = .smart
    var quality = 0.8
    var reduceColors = true
    var pngColors = 128.0
    var dither = true
    var resize = ResizeSpec()

    func options(for f: ImageFormat) -> EncodeOptions {
        switch level {
        case .lossless: EncodeOptions(format: f, quality: 1, lossless: true)
        case .smart: EncodeOptions(format: f, quality: f.smartQuality, pngColors: 256)
        case .custom: EncodeOptions(format: f, quality: quality, pngColors: reduceColors ? Int(pngColors) : 0, dither: dither)
        }
    }
}

struct PipelineResult {
    let data: Data
    let format: ImageFormat
    let image: CGImage
    let unchanged: Bool
}

enum Pipeline {
    static func run(_ src: LoadedImage, _ original: Data, _ s: PipelineSettings) -> PipelineResult? {
        let format = s.format ?? src.format ?? .png
        let target = s.resize.target(for: src.image.size)
        let data: Data?
        var image = src.image
        if src.isAnimated, format == .gif {
            let frames = src.frames.map { (target.map($0.image.resized) ?? $0.image, $0.delay) }
            data = Encoder.animatedGIF(frames)
            image = frames[0].0
        } else {
            if let target { image = image.resized(to: target) }
            data = Encoder.encode(image, s.options(for: format))
        }
        guard var out = data else { return nil }
        // Never hand back something bigger than what came in, when nothing else changed.
        var unchanged = false
        if target == nil, format == src.format, out.count >= original.count { out = original; unchanged = true }
        let preview = unchanged ? src.image : (ImageIOKit.load(out)?.image ?? image)
        return PipelineResult(data: out, format: format, image: preview, unchanged: unchanged)
    }
}

struct BatchItem: Identifiable {
    let id = UUID()
    let url: URL
    let data: Data
    let source: LoadedImage
    var result: PipelineResult?
    var busy = true
    var failed = false
    var name: String { url.deletingPathExtension().lastPathComponent }

    init?(url: URL) {
        guard let d = try? Data(contentsOf: url), let s = ImageIOKit.load(d) else { return nil }
        self.url = url; data = d; source = s
    }

    var saving: Double? {
        guard let r = result else { return nil }
        return 1 - Double(r.data.count) / Double(data.count)
    }
}

@MainActor @Observable
final class BatchModel {
    let mode: Tool
    var items: [BatchItem] = []
    var selection: UUID?
    var settings = PipelineSettings() { didSet { if settings != oldValue { process() } } }
    @ObservationIgnored private var generation = 0

    init(mode: Tool) {
        self.mode = mode
        switch mode {
        case .convert:
            settings.format = .webp
            settings.level = .custom
            settings.quality = 0.85
            settings.reduceColors = false
        default: break
        }
    }

    var selected: BatchItem? { items.first { $0.id == selection } ?? items.first }
    var busy: Bool { items.contains(where: \.busy) }
    var totalIn: Int { items.reduce(0) { $0 + $1.data.count } }
    var totalOut: Int { items.reduce(0) { $0 + ($1.result?.data.count ?? $1.data.count) } }

    func add(_ urls: [URL]) {
        Task {
            let loaded = await withTaskGroup(of: (Int, BatchItem?).self) { g in
                for (i, u) in urls.enumerated() { g.addTask { (i, BatchItem(url: u)) } }
                return await g.reduce(into: []) { $0.append($1) }.sorted { $0.0 < $1.0 }.compactMap(\.1)
            }
            items += loaded
            if selection == nil { selection = loaded.first?.id }
            process(loaded.map(\.id))
        }
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        if selection == id { selection = items.first?.id }
    }

    /// Re-encodes the given items (or all) on every core; stale results are dropped.
    func process(_ ids: [UUID]? = nil) {
        if ids == nil { generation += 1 }
        let gen = generation, s = settings
        let targets = Set(ids ?? items.map(\.id))
        var jobs: [(UUID, LoadedImage, Data)] = []
        for i in items.indices where targets.contains(items[i].id) {
            items[i].busy = true
            jobs.append((items[i].id, items[i].source, items[i].data))
        }
        Task {
            await withTaskGroup(of: (UUID, PipelineResult?).self) { g in
                var queue = jobs[...]
                func enqueue() {
                    guard let (id, src, data) = queue.popFirst() else { return }
                    g.addTask { (id, Pipeline.run(src, data, s)) }
                }
                for _ in 0..<ProcessInfo.processInfo.activeProcessorCount { enqueue() }
                for await (id, result) in g {
                    if gen == generation, let i = items.firstIndex(where: { $0.id == id }) {
                        items[i].result = result
                        items[i].failed = result == nil
                        items[i].busy = false
                    }
                    enqueue()
                }
            }
        }
    }

    func outputName(_ item: BatchItem) -> String {
        switch mode {
        case .compress:
            item.result.map { $0.image.width != item.source.image.width } == true
                ? "\(item.name)-\(item.result!.image.width)w-min" : "\(item.name)-min"
        default: item.name
        }
    }

    func saveAll(_ only: [BatchItem]? = nil) {
        guard let folder = Inbox.chooseFolder() else { return }
        for item in only ?? items {
            guard let r = item.result else { continue }
            try? r.data.write(to: Inbox.unique(folder, outputName(item), r.format.ext))
        }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    /// Temp file used for drag-out.
    func tempFile(_ item: BatchItem) -> URL? {
        guard let r = item.result else { return nil }
        return Inbox.temp(r.data, name: outputName(item), ext: r.format.ext)
    }
}

// MARK: - View

struct BatchToolView: View {
    @Bindable var model: BatchModel
    let tool: Tool
    @Environment(AppState.self) private var state

    var body: some View {
        ToolScaffold(tool: tool) {
            if model.items.isEmpty {
                DropZone(tool: tool) { state.open($0) }
            } else {
                VStack(spacing: 0) {
                    Group {
                        if let item = model.selected {
                            CompareView(before: item.source.image, after: item.result?.image).id(item.id)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    Divider()
                    fileList.frame(height: 200)
                }
            }
        } inspector: {
            ForEach(sections, id: \.self) { section($0) }
            summary
        }
        .toolbar {
            if !model.items.isEmpty {
                Button { state.open(Inbox.openPanel()) } label: { Label("Add Images", systemImage: "plus") }
                Button { model.items.removeAll(); model.selection = nil } label: { Label("Clear", systemImage: "trash") }
            }
        }
    }

    private var sections: [String] {
        switch tool {
        case .convert: ["format", "quality", "resize"]
        default: ["quality", "resize", "format"]
        }
    }

    @ViewBuilder private func section(_ id: String) -> some View {
        switch id {
        case "format": formatPanel
        case "quality": qualityPanel
        default: resizePanel
        }
    }

    // MARK: Inspector panels

    private var formatPanel: some View {
        Panel(title: "Output Format", symbol: "doc.badge.gearshape") {
            if tool == .convert {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
                    ForEach(ImageFormat.common + [.ico, .icns, .bmp, .jp2]) { f in formatTile(f) }
                }
            } else {
                Picker("Format", selection: $model.settings.format) {
                    Text("Keep original").tag(ImageFormat?.none)
                    Divider()
                    ForEach(ImageFormat.common) { Text($0.label).tag(ImageFormat?.some($0)) }
                }
                .labelsHidden()
            }
        }
    }

    private func formatTile(_ f: ImageFormat) -> some View {
        let on = model.settings.format == f
        return Button { model.settings.format = f } label: {
            VStack(spacing: 2) {
                Text(f.ext.uppercased()).font(.system(.headline, design: .rounded).weight(.bold))
                Text(f.blurb).font(.system(size: 9)).foregroundStyle(on ? .white.opacity(0.85) : .secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(on ? AnyShapeStyle(tool.tint.gradient) : AnyShapeStyle(.quaternary.opacity(0.6)),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundStyle(on ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private var qualityPanel: some View {
        Panel(title: "Compression", symbol: "dial.medium") {
            Picker("Level", selection: $model.settings.level) {
                ForEach(CompressionLevel.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            Text(model.settings.level.note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.settings.level == .custom {
                SliderRow(label: "Quality (JPEG · WebP · HEIC · AVIF)", value: $model.settings.quality, range: 0.05...1) { "\(Int($0 * 100))%" }
                Toggle("Reduce PNG colors", isOn: $model.settings.reduceColors)
                if model.settings.reduceColors {
                    SliderRow(label: "Palette", value: $model.settings.pngColors, range: 2...256, step: 1) { "\(Int($0)) colors" }
                    Toggle("Dither", isOn: $model.settings.dither)
                }
            }
        }
    }

    private var resizePanel: some View {
        Panel(title: "Resize", symbol: "aspectratio") {
            Picker("Mode", selection: $model.settings.resize.mode) {
                ForEach(ResizeMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            let r = $model.settings.resize
            switch r.wrappedValue.mode {
            case .none: Text("Keeps original dimensions.").font(.caption).foregroundStyle(.secondary)
            case .width: NumberField(label: "Width", value: r.width)
            case .height: NumberField(label: "Height", value: r.height)
            case .fit, .exact:
                HStack { NumberField(label: "W", value: r.width); NumberField(label: "H", value: r.height) }
                Text(r.wrappedValue.mode == .fit ? "Fits inside the box, keeps aspect ratio." : "Stretches to exactly this size.")
                    .font(.caption).foregroundStyle(.secondary)
            case .percent: SliderRow(label: "Scale", value: r.percent, range: 1...400) { "\(Int($0))%" }
            }
            if [.width, .height].contains(r.wrappedValue.mode) {
                HStack(spacing: 6) {
                    ForEach([256.0, 512, 1080, 1440, 1920], id: \.self) { v in
                        Button("\(Int(v))") {
                            if r.wrappedValue.mode == .width { r.wrappedValue.width = v } else { r.wrappedValue.height = v }
                        }
                        .controlSize(.small)
                    }
                }
            }
            if r.wrappedValue.mode != .none, r.wrappedValue.mode != .exact {
                Toggle("Allow enlarging", isOn: r.allowUpscale)
            }
        }
    }

    private var summary: some View {
        Panel(title: "Result", symbol: "chart.bar.xaxis") {
            if model.items.isEmpty {
                Text("Nothing yet — drop some images.").foregroundStyle(.secondary)
            } else {
                let saved = 1 - Double(model.totalOut) / Double(max(model.totalIn, 1))
                HStack(alignment: .firstTextBaseline) {
                    Text(saved >= 0 ? "−\(Int(saved * 100))%" : "+\(Int(-saved * 100))%")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(saved >= 0 ? AnyShapeStyle(tool.tint.gradient) : AnyShapeStyle(.orange))
                        .contentTransition(.numericText())
                    if model.busy { ProgressView().controlSize(.small) }
                }
                Text("\(model.items.count) image\(model.items.count == 1 ? "" : "s") · \(model.totalIn.bytes) → \(model.totalOut.bytes)")
                    .font(.callout).foregroundStyle(.secondary)
                Button { model.saveAll() } label: {
                    Label("Save All to Folder…", systemImage: "square.and.arrow.down.on.square").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(tool.tint).disabled(model.busy)
                Text("Tip: drag any row out to Finder, Figma or Slack.").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: File list

    private var fileList: some View {
        List(selection: $model.selection) {
            ForEach(model.items) { item in
                row(item).tag(item.id)
                    .onDrag {
                        model.tempFile(item).flatMap { NSItemProvider(contentsOf: $0) } ?? NSItemProvider()
                    }
                    .contextMenu {
                        Button("Save…") { model.saveAll([item]) }
                        Button("Show Original in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                        if let r = item.result {
                            Menu("Send to") {
                                ForEach(Tool.allCases.filter { $0.takesImage && $0 != tool }) { t in
                                    Button(t.title) { state.send(r.image, name: item.name, to: t) }
                                }
                            }
                        }
                        Divider()
                        Button("Remove", role: .destructive) { model.remove(item.id) }
                    }
            }
        }
        .imageDrop { state.open($0) }
    }

    private func row(_ item: BatchItem) -> some View {
        HStack(spacing: 10) {
            PixelImage(image: item.source.image).aspectRatio(contentMode: .fill)
                .frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name).lineLimit(1).font(.callout.weight(.medium))
                    if item.source.isAnimated { Tag("ANIMATED", tint: .orange) }
                }
                HStack(spacing: 4) {
                    Text("\(item.source.format?.label ?? "?") · \(item.source.image.size.dims)")
                    if let r = item.result {
                        Image(systemName: "arrow.right")
                        Text("\(r.format.label) · \(r.image.size.dims)")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if item.busy { ProgressView().controlSize(.small) }
            else if item.failed { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help("Couldn't encode this one") }
            VStack(alignment: .trailing, spacing: 2) {
                Text(item.data.count.bytes).font(.caption).foregroundStyle(.secondary).strikethrough(item.result != nil)
                if let r = item.result { Text(r.data.count.bytes).font(.callout.weight(.semibold)).monospacedDigit() }
            }
            if let s = item.saving {
                Text(item.result?.unchanged == true ? "optimal" : s >= 0 ? "−\(Int(s * 100))%" : "+\(Int(-s * 100))%")
                    .font(.caption.weight(.bold)).monospacedDigit()
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background((s > 0.005 ? Color.green : s < 0 ? .orange : .secondary).opacity(0.18), in: Capsule())
                    .foregroundStyle(s > 0.005 ? Color.green : s < 0 ? .orange : .secondary)
                    .frame(width: 64, alignment: .trailing)
            }
        }
        .padding(.vertical, 2)
    }
}
