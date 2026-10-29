import SwiftUI
import UniformTypeIdentifiers

@main
struct ZemyApp: App {
    @State private var state = AppState()

    init() { NSApplication.shared.setActivationPolicy(.regular) }

    var body: some Scene {
        WindowGroup("Zemy") {
            ContentView()
                .environment(state)
                .frame(minWidth: 1040, minHeight: 660)
                .onAppear {
                    state.installPasteMonitor()
                    #if DEBUG
                    state.runSnapshotsIfRequested()
                    #endif
                }
                .onOpenURL { state.open([$0]) }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open…") { state.open(Inbox.openPanel()) }.keyboardShortcut("o")
            }
            CommandMenu("Tools") {
                ForEach(Array(Tool.allCases.enumerated()), id: \.element) { i, tool in
                    if i < 9 {
                        Button(tool.title) { state.tool = tool }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                    } else {
                        Button(tool.title) { state.tool = tool }
                    }
                }
            }
        }
    }
}

// MARK: - Tools

enum Tool: String, CaseIterable, Identifiable {
    case showcase, svg, icons, favicon, compress, convert, rename, background, colors

    var id: Self { self }
    var title: String {
        switch self {
        case .compress: "Compress & Resize"
        case .convert: "Convert"
        case .rename: "Batch Rename"
        case .background: "Remove Background"
        case .colors: "Color Picker"
        case .svg: "SVG Studio"
        case .showcase: "Showcase"
        case .icons: "App Icons"
        case .favicon: "Favicon"
        }
    }
    var subtitle: String {
        switch self {
        case .compress: "Smaller files, exact sizes"
        case .convert: "PNG · JPEG · WebP · HEIC · AVIF and more"
        case .rename: "Patterns, numbering & case, with undo"
        case .background: "On-device subject lift"
        case .colors: "Sample, palette, contrast"
        case .svg: "Paste, preview, rasterize"
        case .showcase: "Screenshots, type & gradients for web and social"
        case .icons: "macOS, iOS & Android sets"
        case .favicon: "Browser icons, previewed in real tabs"
        }
    }
    var symbol: String {
        switch self {
        case .compress: "arrow.down.right.and.arrow.up.left"
        case .convert: "arrow.triangle.2.circlepath"
        case .rename: "character.cursor.ibeam"
        case .background: "person.crop.rectangle.badge.plus"
        case .colors: "eyedropper.halffull"
        case .svg: "scribble.variable"
        case .showcase: "rectangle.on.rectangle.angled"
        case .icons: "app.badge"
        case .favicon: "globe"
        }
    }
    var tint: Color {
        switch self {
        case .compress: .green
        case .convert: .blue
        case .rename: .brown
        case .background: .purple
        case .colors: .pink
        case .svg: .yellow
        case .showcase: .mint
        case .icons: .red
        case .favicon: .cyan
        }
    }
    var isBatch: Bool { [.compress, .convert].contains(self) }
    var takesImage: Bool { isBatch || [.background, .colors, .icons, .favicon, .showcase].contains(self) }

    static let groups: [(String, [Tool])] = [
        ("Create", [.showcase, .svg, .icons, .favicon]),
        ("Batch", [.compress, .convert, .rename]),
        ("Inspect & Edit", [.background, .colors]),
    ]
}

// MARK: - App state

struct WorkImage: Identifiable {
    let id = UUID()
    let image: CGImage
    let name: String
}

@MainActor @Observable
final class AppState {
    var tool: Tool = .showcase
    /// The image shared by the single-image tools; flows between them.
    var current: WorkImage?

    let batches: [Tool: BatchModel] = Dictionary(uniqueKeysWithValues: [Tool.compress, .convert].map { ($0, BatchModel(mode: $0)) })
    let background = BackgroundModel()
    let colors = ColorModel()
    let svg = SVGModel()
    let showcase = ShowcaseModel()
    let icons = IconModel()
    let favicon = FaviconModel()
    let rename = RenameModel()

    func open(_ urls: [URL]) {
        if tool == .rename { rename.add(urls); return }
        if tool == .showcase {
            let files = Inbox.expand(urls)
            Task.detached {
                let images = files.compactMap { (try? Data(contentsOf: $0)).flatMap(ImageIOKit.load)?.image }
                await MainActor.run { self.showcase.add(images) }
            }
            return
        }
        let urls = Inbox.expand(urls)
        guard let first = urls.first else { return }
        if first.pathExtension.lowercased() == "svg" {
            svg.load(first)
            tool = .svg
            return
        }
        batches[tool]?.add(urls)
        // The first image also becomes the working image for the single-image tools.
        Task.detached {
            guard let data = try? Data(contentsOf: first), let img = ImageIOKit.load(data)?.image else { return }
            let w = WorkImage(image: img, name: first.deletingPathExtension().lastPathComponent)
            await MainActor.run {
                self.current = w
                if !self.tool.takesImage { self.tool = .colors }
            }
        }
    }

    /// Hands an image produced by one tool to another.
    func send(_ img: CGImage, name: String, to target: Tool) {
        current = WorkImage(image: img, name: name)
        if let batch = batches[target], let png = img.pngData, let url = Inbox.temp(png, name: name, ext: "png") {
            batch.add([url])
        }
        if target == .showcase { showcase.add([img]) }
        tool = target
    }

    /// ⌘V anywhere that isn't a text field: images, image files or SVG markup.
    @discardableResult
    func paste() -> Bool {
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            open(urls); return true
        }
        if let s = pb.string(forType: .string), s.range(of: "<svg", options: .caseInsensitive) != nil {
            svg.source = s; tool = .svg; return true
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff, NSPasteboard.PasteboardType(UTType.jpeg.identifier)] {
            if let data = pb.data(forType: type), let url = Inbox.temp(data, name: "Pasted", ext: type == .png ? "png" : type == .tiff ? "tiff" : "jpg") {
                open([url]); return true
            }
        }
        return false
    }

    private var monitor: Any?
    func installPasteMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  e.charactersIgnoringModifiers == "v",
                  !(NSApp.keyWindow?.firstResponder is NSText) else { return e }
            return self.paste() ? nil : e
        }
    }
}

// MARK: - Root view

struct ContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            List(selection: $state.tool) {
                ForEach(Tool.groups, id: \.0) { group, tools in
                    Section(group) {
                        ForEach(tools) { tool in
                            Label { Text(tool.title) } icon: { ToolIcon(tool: tool) }
                                .tag(tool)
                                .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230)
            .safeAreaInset(edge: .bottom) { CurrentImageChip() }
        } detail: {
            detail.id(state.tool)
        }
        .imageDrop { state.open($0) }
    }

    @ViewBuilder private var detail: some View {
        switch state.tool {
        case .compress, .convert: BatchToolView(model: state.batches[state.tool]!, tool: state.tool)
        case .background: BackgroundToolView(model: state.background)
        case .colors: ColorToolView(model: state.colors)
        case .svg: SVGToolView(model: state.svg)
        case .showcase: ShowcaseToolView(model: state.showcase)
        case .icons: IconToolView(model: state.icons)
        case .favicon: FaviconToolView(model: state.favicon)
        case .rename: RenameToolView(model: state.rename)
        }
    }
}

/// Shows the shared working image at the bottom of the sidebar.
struct CurrentImageChip: View {
    @Environment(AppState.self) private var state
    var body: some View {
        if let cur = state.current {
            HStack(spacing: 10) {
                PixelImage(image: cur.image).aspectRatio(contentMode: .fill)
                    .frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 1) {
                    Text(cur.name).font(.caption.weight(.medium)).lineLimit(1)
                    Text(cur.image.size.dims).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button { state.current = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
            }
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            .padding(10)
            .help("Working image — shared by Remove Background, Colors and App Icons")
        }
    }
}

/// Wraps single-image tools: drop zone until there is a working image.
struct SingleImageTool<Canvas: View, Inspector: View>: View {
    let tool: Tool
    @ViewBuilder var canvas: (WorkImage) -> Canvas
    @ViewBuilder var inspector: Inspector
    @Environment(AppState.self) private var state

    var body: some View {
        ToolScaffold(tool: tool) {
            if let cur = state.current { canvas(cur) } else { DropZone(tool: tool, multiple: false) { state.open($0) } }
        } inspector: {
            inspector
        }
        .toolbar {
            if state.current != nil {
                Button { state.open(Inbox.openPanel(multiple: false)) } label: { Label("Replace Image", systemImage: "photo.badge.plus") }
            }
        }
    }
}
