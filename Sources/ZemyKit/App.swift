import SwiftUI
import UniformTypeIdentifiers

public struct ZemyApp: App {
    @State private var state = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @AppStorage("clipboard.menubar") private var showMenuBar = true

    public init() { NSApplication.shared.setActivationPolicy(.regular) }

    public var body: some Scene {
        WindowGroup("Zemy", id: "main") {
            ContentView()
                .environment(state)
                .frame(minWidth: 1040, minHeight: 660)
                .onAppear {
                    delegate.state = state
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
                ForEach(Array(Tool.visible.enumerated()), id: \.element) { i, tool in
                    if i < 9 {
                        Button(tool.title) { state.tool = tool }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                    } else {
                        Button(tool.title) { state.tool = tool }
                    }
                }
            }
        }

        // Clipboard history in the menu bar (can be hidden from the Clipboard tool).
        // MenuBarExtra echoes isInserted on every update; writing it unconditionally loops via UserDefaults.
        MenuBarExtra(isInserted: Binding(
            get: { showMenuBar },
            set: { if $0 != showMenuBar { showMenuBar = $0 } }
        )) {
            ClipboardMenuBarView(model: state.clipboard) { state.showClipboard() }
                .environment(state)
        } label: {
            Image(nsImage: .zemyMenuBar).accessibilityLabel("Zemy Clipboard")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Dock menu: recent clipboard items, one click to copy again.
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var state: AppState?

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let state else { return nil }
        return state.clipboard.dockMenu { [weak state] in state?.showClipboard() }
    }
}

// MARK: - Tools

enum Tool: String, CaseIterable, Identifiable {
    case showcase, appstore, svg, icons, favicon, compress, convert, rename, background, colors, clipboard

    var id: Self { self }
    var title: String {
        switch self {
        case .compress: "Compress & Resize"
        case .convert: "Convert"
        case .rename: "Batch Rename"
        case .background: "Remove Background"
        case .colors: "Color Picker"
        case .clipboard: "Clipboard"
        case .svg: "SVG Studio"
        case .showcase: "Showcase"
        case .appstore: "App Store"
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
        case .clipboard: "Your recent copies, one click away"
        case .svg: "Paste, preview, rasterize"
        case .showcase: "Screenshots, type & gradients for web and social"
        case .appstore: "iPhone & iPad screenshot sets in every language"
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
        case .clipboard: "doc.on.clipboard"
        case .svg: "scribble.variable"
        case .showcase: "rectangle.on.rectangle.angled"
        case .appstore: "apps.iphone"
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
        case .clipboard: .teal
        case .svg: .yellow
        case .showcase: .mint
        case .appstore: .indigo
        case .icons: .red
        case .favicon: .cyan
        }
    }
    var isBatch: Bool { [.compress, .convert].contains(self) }
    var takesImage: Bool { isBatch || [.background, .colors, .icons, .favicon, .showcase, .appstore].contains(self) }

    // .icons hidden until Android adaptive layers are supported
    static let visible = allCases.filter { $0 != .icons }

    static let groups: [(String, [Tool])] = [
        ("Create", [.showcase, .appstore, .svg, .favicon]),
        ("Batch", [.compress, .convert, .rename]),
        ("Inspect & Edit", [.background, .colors]),
        ("Utilities", [.clipboard]),
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
    let clipboard = ClipboardModel()
    /// Opens a main window (set by the window itself, so it also works after the window was closed).
    @ObservationIgnored var openMainWindow: (() -> Void)?

    /// Brings Zemy forward on the Clipboard tool (from the Dock menu or the menu bar).
    func showClipboard() {
        tool = .clipboard
        NSApp.activate(ignoringOtherApps: true)
        if let w = NSApp.windows.first(where: { $0.canBecomeMain && $0.styleMask.contains(.titled) }) {
            w.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
    }
    /// The image shared by the single-image tools; flows between them.
    var current: WorkImage?

    let batches: [Tool: BatchModel] = Dictionary(uniqueKeysWithValues: [Tool.compress, .convert].map { ($0, BatchModel(mode: $0)) })
    let background = BackgroundModel()
    let colors = ColorModel()
    let svg = SVGModel()
    let showcase = ShowcaseModel()
    let store = StoreModel()
    let icons = IconModel()
    let favicon = FaviconModel()
    let rename = RenameModel()

    func open(_ urls: [URL]) {
        if tool == .rename { rename.add(urls); return }
        if tool == .favicon { favicon.load(urls); return }
        if tool == .showcase || tool == .appstore {
            let files = Inbox.expand(urls), target = tool
            Task.detached {
                let images = files.compactMap { (try? Data(contentsOf: $0)).flatMap(ImageIOKit.load)?.image }
                await MainActor.run { target == .showcase ? self.showcase.add(images) : self.store.add(images) }
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
        if target == .appstore { store.add([img]) }
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
    @Environment(\.openWindow) private var openWindow

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
        } detail: {
            detail.id(state.tool)
        }
        .imageDrop { state.open($0) }
        .onAppear { state.openMainWindow = { [openWindow] in openWindow(id: "main") } }
    }

    @ViewBuilder private var detail: some View {
        switch state.tool {
        case .compress, .convert: BatchToolView(model: state.batches[state.tool]!, tool: state.tool)
        case .background: BackgroundToolView(model: state.background)
        case .colors: ColorToolView(model: state.colors)
        case .clipboard: ClipboardToolView(model: state.clipboard)
        case .svg: SVGToolView(model: state.svg)
        case .showcase: ShowcaseToolView(model: state.showcase)
        case .appstore: AppStoreToolView(model: state.store)
        case .icons: IconToolView(model: state.icons)
        case .favicon: FaviconToolView(model: state.favicon)
        case .rename: RenameToolView(model: state.rename)
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
                Button { state.current = nil } label: { Label("Clear", systemImage: "trash") }
            }
        }
    }
}

extension NSImage {
    /// Template glyph of the app icon's multitool: handle plus three blades fanned from one rivet.
    static let zemyMenuBar: NSImage = {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let ctx = NSGraphicsContext.current!.cgContext
            let pivot = CGPoint(x: 3.5, y: 3.5)
            func pill(_ deg: CGFloat, length: CGFloat, width: CGFloat) {
                ctx.saveGState()
                ctx.translateBy(x: pivot.x, y: pivot.y)
                ctx.rotate(by: deg * .pi / 180)
                ctx.addPath(CGPath(roundedRect: CGRect(x: -width / 2, y: -width / 2, width: length + width / 2, height: width),
                                   cornerWidth: width / 2, cornerHeight: width / 2, transform: nil))
                ctx.fillPath()
                ctx.restoreGState()
            }
            ctx.setFillColor(.black)
            pill(4, length: 13, width: 4)
            for deg: CGFloat in [32, 58, 84] { pill(deg, length: 12, width: 2.4) }
            ctx.setBlendMode(.clear)
            ctx.fillEllipse(in: CGRect(x: pivot.x - 0.9, y: pivot.y - 0.9, width: 1.8, height: 1.8))
            return true
        }
        img.isTemplate = true
        return img
    }()
}
