import SwiftUI
import WebKit
import UniformTypeIdentifiers

@MainActor @Observable
final class SVGModel {
    var source = """
    <svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
      <defs>
        <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stop-color="#FF6B6B"/><stop offset="1" stop-color="#8C52FF"/>
        </linearGradient>
      </defs>
      <rect x="16" y="16" width="224" height="224" rx="56" fill="url(#g)"/>
      <path d="M128 64 L192 176 H64 Z" fill="none" stroke="#fff" stroke-width="14" stroke-linejoin="round"/>
    </svg>
    """
    var background = 0 // 0 checker, 1 white, 2 black
    var name = "vector"

    func load(_ url: URL) {
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { return }
        source = s
        name = url.deletingPathExtension().lastPathComponent
    }

    /// Intrinsic size from width/height, falling back to the viewBox.
    var size: CGSize {
        func attr(_ name: String) -> String? {
            guard let open = source.range(of: "<svg[^>]*>", options: .regularExpression),
                  let r = source[open].range(of: "\\s\(name)\\s*=\\s*[\"']([^\"']+)[\"']", options: .regularExpression) else { return nil }
            return String(source[open][r]).components(separatedBy: CharacterSet(charactersIn: "\"'"))[1]
        }
        let num = { (s: String?) in s.flatMap { Double($0.trimmingCharacters(in: .letters.union(.whitespaces))) } }
        let vb = attr("viewBox")?.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
        let w = num(attr("width")) ?? vb.flatMap { $0.count == 4 ? $0[2] : nil } ?? 512
        let h = num(attr("height")) ?? vb.flatMap { $0.count == 4 ? $0[3] : nil } ?? 512
        return CGSize(width: max(w, 1), height: max(h, 1))
    }

    var isValid: Bool { source.range(of: "<svg", options: .caseInsensitive) != nil }

    /// Strips comments, metadata, editor cruft and whitespace between tags.
    var minified: String {
        var s = source
        for pattern in ["<!--[\\s\\S]*?-->", "<\\?xml[^>]*\\?>", "<!DOCTYPE[^>]*>", "<metadata[\\s\\S]*?</metadata>",
                        "<sodipodi:[^>]*/>", "\\s(inkscape|sodipodi|data-name|xml:space)[:\\w-]*=\"[^\"]*\""] {
            s = s.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        s = s.replacingOccurrences(of: ">\\s+<", with: "><", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Indented, one element per line (great for minified exports from design tools).
    var formatted: String {
        guard let doc = try? XMLDocument(xmlString: source, options: [.nodePreserveAll]) else { return source }
        doc.documentContentKind = .xml
        return doc.rootElement()?.xmlString(options: [.nodePrettyPrint, .nodePreserveAll]) ?? source
    }

    var dataURI: String { "data:image/svg+xml;base64," + Data(minified.utf8).base64EncodedString() }
}

// MARK: - Rendering via WebKit (full SVG spec: filters, masks, CSS, text)

@MainActor
enum SVGRenderer {
    /// Scripts off for every SVG web view (belt and braces with the CSP below).
    static var config: WKWebViewConfiguration {
        let c = WKWebViewConfiguration()
        c.defaultWebpagePreferences.allowsContentJavaScript = false
        return c
    }

    static func html(_ svg: String, fill: Bool) -> String {
        let css = fill ? "svg{width:100vw;height:100vh;display:block}"
                       : "body{display:flex;align-items:center;justify-content:center;height:100vh}svg{max-width:92vw;max-height:92vh;width:100%;height:100%}"
        // CSP: nothing may load from the network and no scripts run — only the pasted markup and inline data.
        let csp = "<meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; img-src data: blob:; style-src 'unsafe-inline'; font-src data:\">"
        return "<html><head>\(csp)<meta name=viewport content='width=device-width'><style>html,body{margin:0;background:transparent;overflow:hidden}\(css)</style></head><body>\(svg)</body></html>"
    }

    static func render(_ svg: String, size: CGSize, scale: Double) async -> CGImage? {
        let web = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        let loader = Loader()
        web.navigationDelegate = loader
        await withCheckedContinuation { c in
            loader.done = { c.resume() }
            web.loadHTMLString(html(svg, fill: true), baseURL: nil)
        }
        let backing = NSScreen.main?.backingScaleFactor ?? 2
        let config = WKSnapshotConfiguration()
        config.rect = web.bounds
        config.snapshotWidth = NSNumber(value: size.width * scale / backing)
        guard let ns = try? await web.takeSnapshot(configuration: config) else { return nil }
        var rect = CGRect(origin: .zero, size: ns.size)
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        return ns.cgImage(forProposedRect: &rect, context: nil, hints: nil)?.resized(to: target)
    }

    final class Loader: NSObject, WKNavigationDelegate {
        var done: (() -> Void)?
        func webView(_ w: WKWebView, didFinish _: WKNavigation!) { done?(); done = nil }
        func webView(_ w: WKWebView, didFail _: WKNavigation!, withError _: Error) { done?(); done = nil }
    }
}

struct SVGPreview: NSViewRepresentable {
    let svg: String
    func makeNSView(context: Context) -> WKWebView {
        let v = WKWebView(frame: .zero, configuration: SVGRenderer.config)
        v.setValue(false, forKey: "drawsBackground")
        return v
    }
    func updateNSView(_ v: WKWebView, context: Context) {
        let html = SVGRenderer.html(svg, fill: false)
        if context.coordinator.last != html { context.coordinator.last = html; v.loadHTMLString(html, baseURL: nil) }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var last = "" }
}

// MARK: - View

struct SVGToolView: View {
    @Bindable var model: SVGModel
    @State private var dropping = false

    /// SVG data straight from a browser drag, or a .svg file from Finder.
    private func loadDrop(_ providers: [NSItemProvider]) {
        if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.svg.identifier) && !$0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            p.loadDataRepresentation(forTypeIdentifier: UTType.svg.identifier) { data, _ in
                guard let data, let s = String(data: data, encoding: .utf8) else { return }
                DispatchQueue.main.async { model.source = s; model.name = "vector" }
            }
            return
        }
        Inbox.load(providers) { urls in
            if let u = urls.first(where: { $0.pathExtension.lowercased() == "svg" }) { model.load(u) }
        }
    }

    var body: some View {
        ToolScaffold(tool: .svg) {
            GeometryReader { geo in
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Button { if let u = Inbox.openPanel(multiple: false, types: [.svg]).first { model.load(u) } } label: {
                            Label("Upload SVG…", systemImage: "square.and.arrow.up")
                        }
                        Button("Paste") { if let s = NSPasteboard.general.string(forType: .string) { model.source = s; model.name = "vector" } }
                        Spacer()
                        Button("Format") { model.source = model.formatted }
                        Button("Minify") { model.source = model.minified }
                    }
                    .controlSize(.small).padding(8)
                    Divider()
                    TextEditor(text: $model.source)
                        .font(.system(size: 12, design: .monospaced))
                        .autocorrectionDisabled()
                        .scrollContentBackground(.hidden)
                }
                .frame(width: max(220, geo.size.width * 0.42))
                .background(.background)
                Divider()
                ZStack {
                    switch model.background {
                    case 1: Color.white
                    case 2: Color.black
                    default: Checkerboard(cell: 10)
                    }
                    if model.isValid { SVGPreview(svg: model.source) }
                    else { ContentUnavailableView("Paste SVG markup", systemImage: "scribble.variable", description: Text("Or drop a .svg file here.")) }
                    if dropping {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Tool.svg.tint, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                            .background(Tool.svg.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay { Label("Drop SVG to load its code", systemImage: "arrow.down.doc").font(.title3.weight(.semibold)) }
                            .padding(16)
                    }
                }
                .onDrop(of: [.svg, .fileURL], isTargeted: $dropping) { providers in loadDrop(providers); return true }
                .overlay(alignment: .bottom) {
                    Picker("", selection: $model.background) {
                        Image(systemName: "checkerboard.rectangle").tag(0)
                        Image(systemName: "sun.max").tag(1)
                        Image(systemName: "moon").tag(2)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    .padding(6).background(.regularMaterial, in: Capsule()).padding(12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            }
        } inspector: {
            Panel(title: "Info", symbol: "info.circle") {
                ValueRow(label: "Size", value: model.size.dims)
                ValueRow(label: "Bytes", value: "\(model.source.utf8.count.bytes) → \(model.minified.utf8.count.bytes) minified")
            }
            Panel(title: "Copy As", symbol: "doc.on.clipboard") {
                HStack {
                    CopyButton(text: { model.minified }, label: "Minified")
                    CopyButton(text: { model.dataURI }, label: "Data URI")
                }
                CopyButton(text: { "background-image: url(\"\(model.dataURI)\");" }, label: "CSS background")
            }
            ExportPanel(id: "svg", name: model.name, formats: [.png, .webp, .jpeg, .heic, .avif, .tiff, .pdf, .ico, .icns],
                        scales: [1, 2, 3, 4, 8],
                        extras: [ExportOption(label: "SVG (minified)", name: "\(model.name).svg") { Data(model.minified.utf8) }]) { s in
                await SVGRenderer.render(model.source, size: model.size, scale: s)
            }
        }
    }
}
