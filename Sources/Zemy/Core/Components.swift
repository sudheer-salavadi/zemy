import SwiftUI
import UniformTypeIdentifiers

// MARK: - Formatting & small helpers

extension Int { var bytes: String { ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file) } }
extension CGSize { var dims: String { "\(Int(width)) × \(Int(height))" } }
extension Color {
    var cg: CGColor { NSColor(self).usingColorSpace(.sRGB)?.cgColor ?? .black }
    var ci: CIColor { CIColor(cgColor: cg) }
}

enum Clipboard {
    static func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
    static func copy(_ img: CGImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let png = img.pngData { pb.setData(png, forType: .png) }
        pb.writeObjects([NSImage(cgImage: img, size: img.size)])
    }
}

// MARK: - File inbox (drop, paste, open panel all funnel into [URL])

enum Inbox {
    static let tempDir: URL = {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("Zemy", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()

    static func temp(_ data: Data, name: String, ext: String) -> URL? {
        let dir = tempDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(name).\(ext)")
        return (try? data.write(to: url)) == nil ? nil : url
    }

    /// Folders are expanded to the images (or, with `imagesOnly: false`, all visible files) inside them.
    static func expand(_ urls: [URL], imagesOnly: Bool = true) -> [URL] {
        urls.flatMap { url -> [URL] in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return [url] }
            let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])?.allObjects as? [URL] ?? []
            return files.filter { imagesOnly ? UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true : !$0.hasDirectoryPath }
                .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        }
    }

    /// Resolves dropped items to file URLs, in drop order. Real files keep their location;
    /// data-only drags (browsers, Photos, screenshot thumbnails) become temp copies that keep their original name.
    static func load(_ providers: [NSItemProvider], _ done: @escaping ([URL]) -> Void) {
        // Finder always puts the real file locations on the drag pasteboard, whatever form the
        // item providers take — so prefer those and work on the user's actual files.
        let dragged = NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !dragged.isEmpty {
            DispatchQueue.main.async { done(dragged.map { ($0 as NSURL).filePathURL ?? $0 }) }
            return
        }
        let group = DispatchGroup()
        var urls = [URL?](repeating: nil, count: providers.count)
        let lock = NSLock()
        func set(_ i: Int, _ u: URL?) { lock.lock(); urls[i] = u; lock.unlock(); group.leave() }

        func copyData(_ p: NSItemProvider, _ i: Int) {
            guard let type = p.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else { return set(i, nil) }
            _ = p.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                // The provided file is deleted when this returns, so copy it now under its real name.
                guard let url, let data = try? Data(contentsOf: url) else { return set(i, nil) }
                let name = p.suggestedName.map { ($0 as NSString).deletingPathExtension } ?? url.deletingPathExtension().lastPathComponent
                let ext = url.pathExtension.isEmpty ? (UTType(type)?.preferredFilenameExtension ?? "png") : url.pathExtension
                set(i, temp(data, name: name, ext: ext))
            }
        }

        for (i, p) in providers.enumerated() {
            #if DEBUG
            print("drop provider \(i):", p.registeredTypeIdentifiers, "canLoad NSURL:", p.canLoadObject(ofClass: NSURL.self), "name:", p.suggestedName ?? "-")
            #endif
            group.enter()
            if p.canLoadObject(ofClass: NSURL.self) {
                _ = p.loadObject(ofClass: NSURL.self) { obj, _ in
                    if let u = (obj as? NSURL) as URL?, u.isFileURL { set(i, u) } else { copyData(p, i) }
                }
            } else {
                copyData(p, i)
            }
        }
        group.notify(queue: .main) { done(urls.compactMap { $0 }) }
    }

    /// True for files that only exist as Zemy's temporary copies.
    static func isTempCopy(_ url: URL) -> Bool {
        url.resolvingSymlinksInPath().path.hasPrefix(tempDir.resolvingSymlinksInPath().path) // /var vs /private/var
    }

    static func openPanel(multiple: Bool = true, types: [UTType] = [.image, .folder]) -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = multiple
        panel.canChooseDirectories = types.contains(.folder)
        panel.allowedContentTypes = types
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func chooseFolder(_ prompt: String = "Save Here") -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func save(_ data: Data, name: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { try? data.write(to: url) }
    }

    /// Unique destination inside `folder` (adds " 2", " 3"… on clashes).
    static func unique(_ folder: URL, _ base: String, _ ext: String) -> URL {
        var url = folder.appendingPathComponent("\(base).\(ext)"), n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) \(n).\(ext)"); n += 1
        }
        return url
    }
}

extension View {
    func imageDrop(isTargeted: Binding<Bool>? = nil, perform: @escaping ([URL]) -> Void) -> some View {
        onDrop(of: [.fileURL, .image], isTargeted: isTargeted) { providers in
            Inbox.load(providers, perform)
            return true
        }
    }
}

// MARK: - Canvas pieces

struct Checkerboard: View {
    var cell: CGFloat = 8
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Canvas { ctx, size in
            let dark = scheme == .dark
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: dark ? 0.20 : 0.96)))
            var p = Path()
            for y in 0..<Int(size.height / cell) + 1 {
                for x in 0..<Int(size.width / cell) + 1 where (x + y) % 2 == 0 {
                    p.addRect(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell))
                }
            }
            ctx.fill(p, with: .color(Color(white: dark ? 0.26 : 0.86)))
        }
    }
}

struct PixelImage: View {
    let image: CGImage
    var scale: CGFloat = 1
    var body: some View {
        Image(decorative: image, scale: 1).resizable().interpolation(scale > 2.5 ? .none : .high)
    }
}

/// Fit-to-view canvas with trackpad pinch zoom, drag pan and double-click reset.
/// `content` receives the on-screen points per content pixel.
struct ZoomCanvas<Content: View>: View {
    let size: CGSize
    var checker = true
    /// Off for editors whose content handles its own drags.
    var pannable = true
    @ViewBuilder var content: (CGFloat) -> Content

    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var drag: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let fit = min((geo.size.width - 48) / max(size.width, 1), (geo.size.height - 48) / max(size.height, 1))
            let k = max(fit, 0.01) * zoom * pinch
            ZStack {
                if checker { Checkerboard() }
                content(k)
            }
            .frame(width: size.width * k, height: size.height * k)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            .offset(x: offset.width + drag.width, y: offset.height + drag.height)
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(MagnifyGesture()
                .updating($pinch) { v, s, _ in s = v.magnification }
                .onEnded { zoom = min(max(zoom * $0.magnification, 0.1), 64) })
            .simultaneousGesture(DragGesture(minimumDistance: 6)
                .updating($drag) { v, s, _ in s = v.translation }
                .onEnded { offset.width += $0.translation.width; offset.height += $0.translation.height },
                including: pannable ? .all : .subviews)
            .onTapGesture(count: 2) { withAnimation(.snappy) { zoom = 1; offset = .zero } }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 2) {
                    Button { withAnimation(.snappy) { zoom /= 1.5 } } label: { Image(systemName: "minus") }
                    Text("\(Int(k * 100))%").monospacedDigit().frame(minWidth: 44)
                    Button { withAnimation(.snappy) { zoom *= 1.5 } } label: { Image(systemName: "plus") }
                    Divider().frame(height: 14)
                    Button("Fit") { withAnimation(.snappy) { zoom = 1; offset = .zero } }
                    Button("1:1") { withAnimation(.snappy) { zoom = 1 / max(fit, 0.01) } }
                }
                .buttonStyle(.borderless).font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .padding(12)
            }
        }
        .clipped()
        .contentShape(Rectangle())
    }
}

/// Before/after slider on top of a zoom canvas.
/// The divider lives in an overlay above the canvas (so pan/zoom can't steal its drag);
/// the images are masked at wherever the divider sits on screen.
struct CompareView: View {
    let before: CGImage
    let after: CGImage?
    var labels = ("Original", "Result")
    @State private var splitX: CGFloat? // canvas coordinates; nil = centred

    var body: some View {
        GeometryReader { outer in
            let x = min(max(splitX ?? outer.size.width / 2, 0), outer.size.width)
            ZoomCanvas(size: before.size) { k in
                GeometryReader { g in
                    let local = min(max(x - g.frame(in: .named("compareCanvas")).minX, 0), g.size.width)
                    ZStack(alignment: .topLeading) {
                        PixelImage(image: before, scale: k)
                            .mask(alignment: .leading) { Rectangle().frame(width: after == nil ? g.size.width : local) }
                        if let after {
                            PixelImage(image: after, scale: k)
                                .mask(alignment: .trailing) { Rectangle().frame(width: g.size.width - local) }
                        }
                    }
                }
            }
            .overlay {
                if after != nil {
                    ZStack {
                        Rectangle().fill(.white).frame(width: 2).shadow(color: .black.opacity(0.5), radius: 2)
                        Image(systemName: "arrow.left.and.right")
                            .font(.caption.bold()).foregroundStyle(.black)
                            .frame(width: 30, height: 30).background(.white, in: Circle()).shadow(radius: 3)
                    }
                    .frame(width: 30, height: outer.size.height)
                    .contentShape(Rectangle())
                    .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("compareCanvas"))
                        .onChanged { splitX = min(max($0.location.x, 0), outer.size.width) })
                    .position(x: x, y: outer.size.height / 2)
                }
            }
        }
        .coordinateSpace(name: "compareCanvas")
        .overlay(alignment: .top) {
            if after != nil {
                HStack { Tag(labels.0); Spacer(); Tag(labels.1) }.padding(12).allowsHitTesting(false)
            }
        }
    }
}

struct Tag: View {
    let text: String
    var tint: Color = .secondary
    init(_ text: String, tint: Color = .secondary) { self.text = text; self.tint = tint }
    var body: some View {
        Text(text).font(.caption2.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 3)
            .background(.regularMaterial, in: Capsule()).foregroundStyle(tint)
    }
}

// MARK: - Empty state

struct DropZone: View {
    var tool: Tool
    var multiple = true
    var extra: AnyView? = nil
    var types: [UTType] = [.image, .folder]
    let onURLs: ([URL]) -> Void
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 16) {
            ToolIcon(tool: tool, size: 72)
                .scaleEffect(targeted ? 1.08 : 1)
                .animation(.bouncy, value: targeted)
            Text(types.contains(.item) ? "Drop files or folders" : multiple ? "Drop images or folders" : "Drop an image").font(.title2.weight(.semibold))
            Text("Paste with ⌘V · drag from Figma, Finder or the browser").foregroundStyle(.secondary)
            HStack {
                Button("Choose…") { onURLs(Inbox.openPanel(multiple: multiple, types: types)) }.buttonStyle(.borderedProminent)
                if let extra { extra }
            }
            .controlSize(.large).tint(tool.tint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .foregroundStyle(targeted ? tool.tint : .secondary.opacity(0.35))
                .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(tool.tint.opacity(targeted ? 0.08 : 0.02)))
        }
        .padding(28)
        .imageDrop(isTargeted: $targeted, perform: onURLs)
    }
}

// MARK: - Tool chrome

struct ToolIcon: View {
    let tool: Tool
    var size: CGFloat = 22
    var body: some View {
        Image(systemName: tool.symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [tool.tint.mix(with: .white, by: 0.25), tool.tint], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .shadow(color: tool.tint.opacity(0.3), radius: size * 0.1, y: size * 0.04)
    }
}

/// Canvas on the left, fixed-width inspector panel on the right.
/// A plain HStack (not `.inspector`) so hit-testing always matches what's drawn.
struct ToolScaffold<Canvas: View, Inspector: View>: View {
    let tool: Tool
    @ViewBuilder var canvas: Canvas
    @ViewBuilder var inspector: Inspector
    @AppStorage("showInspector") private var showInspector = true

    var body: some View {
        HStack(spacing: 0) {
            canvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .underPageBackgroundColor))
                .clipped()
                .contentShape(Rectangle())
            if showInspector {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) { inspector }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 310)
                .background(Color(nsColor: .windowBackgroundColor))
                .zIndex(1)
                .transition(.move(edge: .trailing))
            }
        }
        .navigationTitle(tool.title)
        .navigationSubtitle(tool.subtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { withAnimation(.snappy) { showInspector.toggle() } } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
    }
}

struct Panel<Content: View>: View {
    let title: String
    var symbol: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            content
        }
    }
}

struct SliderRow: View {
    let label: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double? = nil
    var format: (Double) -> String = { String(Int($0.rounded())) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                Text(format(value)).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.callout)
            if let step { Slider(value: $value, in: range, step: step) } else { Slider(value: $value, in: range) }
        }
    }
}

struct NumberField: View {
    let label: String
    @Binding var value: Double
    var unit = "px"
    var body: some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary).font(.caption)
            TextField(label, value: $value, format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
            Text(unit).foregroundStyle(.tertiary).font(.caption)
        }
    }
}

struct CopyButton: View {
    let text: () -> String
    var label: String? = nil
    @State private var copied = false
    var body: some View {
        Button {
            Clipboard.copy(text())
            withAnimation { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation { copied = false } }
        } label: {
            if let label { Label(copied ? "Copied" : label, systemImage: copied ? "checkmark" : "doc.on.doc") }
            else { Image(systemName: copied ? "checkmark" : "doc.on.doc").contentTransition(.symbolEffect(.replace)) }
        }
        .help("Copy")
    }
}

/// A row of value + copy, used by colour readouts and info lists.
struct ValueRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 58, alignment: .leading)
            Text(value).font(.system(.callout, design: .monospaced)).textSelection(.enabled).lineLimit(1)
            Spacer(minLength: 4)
            CopyButton(text: { value }).buttonStyle(.borderless)
        }
    }
}

// MARK: - Export panel (shared by every tool that produces an image)

struct ExportOption: Identifiable {
    let label: String
    let name: String
    let data: () async -> Data?
    var id: String { label }
}

struct ExportPanel: View {
    let id: String
    let name: String
    var formats: [ImageFormat] = ImageFormat.common
    var scales: [Double] = []
    var extras: [ExportOption] = []
    let render: (Double) async -> CGImage?

    @Environment(AppState.self) private var state
    @AppStorage private var format: ImageFormat
    @AppStorage private var quality: Double
    @AppStorage private var scale: Double
    @AppStorage private var tinyPNG: Bool
    @State private var busy = false

    init(id: String, name: String, formats: [ImageFormat] = ImageFormat.common, scales: [Double] = [],
         extras: [ExportOption] = [], render: @escaping (Double) async -> CGImage?) {
        self.id = id; self.name = name; self.formats = formats; self.scales = scales; self.extras = extras; self.render = render
        _format = AppStorage(wrappedValue: formats.first ?? .png, "\(id).format")
        _quality = AppStorage(wrappedValue: 0.85, "\(id).quality")
        _scale = AppStorage(wrappedValue: scales.contains(2) ? 2 : 1, "\(id).scale")
        _tinyPNG = AppStorage(wrappedValue: false, "\(id).tinyPNG")
    }

    var body: some View {
        Panel(title: "Export", symbol: "square.and.arrow.up") {
            Picker("Format", selection: $format) {
                ForEach(formats) { Text($0.label).tag($0) }
            }
            if format.isLossy {
                SliderRow(label: "Quality", value: $quality, range: 0.1...1) { "\(Int($0 * 100))%" }
            }
            if format == .png { Toggle("Shrink to 256 colors", isOn: $tinyPNG) }
            if !scales.isEmpty {
                Picker("Scale", selection: $scale) {
                    ForEach(scales, id: \.self) { Text("\(Int($0))×").tag($0) }
                }
                .pickerStyle(.segmented)
            }
            HStack {
                Button { run { data, _ in Inbox.save(data, name: "\(name).\(format.ext)") } } label: {
                    Label("Export…", systemImage: "arrow.down.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                Button { run { _, img in Clipboard.copy(img) } } label: { Image(systemName: "doc.on.doc") }
                    .controlSize(.large).help("Copy image")
                Menu {
                    ForEach(Tool.allCases.filter(\.takesImage)) { t in
                        Button { run { _, img in state.send(img, name: name, to: t) } } label: { Label(t.title, systemImage: t.symbol) }
                    }
                } label: { Image(systemName: "arrowshape.turn.up.right") }
                    .menuIndicator(.hidden).fixedSize().controlSize(.large).help("Send to another tool")
            }
            .disabled(busy)
            ForEach(extras) { opt in
                Button("Export \(opt.label)…") {
                    Task { if let d = await opt.data() { Inbox.save(d, name: opt.name) } }
                }
            }
        }
    }

    private func run(_ then: @escaping (Data, CGImage) -> Void) {
        busy = true
        let opts = EncodeOptions(format: format, quality: quality, pngColors: tinyPNG ? 256 : 0)
        Task {
            defer { busy = false }
            guard let img = await render(scale) else { return }
            let data = await Task.detached { Encoder.encode(img, opts) }.value
            if let data { then(data, img) }
        }
    }
}
