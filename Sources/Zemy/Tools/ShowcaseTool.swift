import SwiftUI

/// Compose screenshots and type over a background, for Dribbble shots, social posts and landing pages.
@MainActor @Observable
final class ShowcaseModel {
    enum Background: String, CaseIterable, Identifiable { case none = "None", color = "Color", mesh = "Mesh", image = "Image"; var id: Self { self } }
    enum Frame: String, CaseIterable, Identifiable { case none = "None", window = "Window", browser = "Browser"; var id: Self { self } }
    enum Layout: String, CaseIterable, Identifiable {
        case hero = "Hero", split = "Split", row = "Side by side", cascade = "Cascade", fan = "Fan", stack = "Stack", bleed = "Bleed", scatter = "Scatter"
        var id: Self { self }
    }
    enum Order { case front, forward, backward, back }
    /// What the screenshots are currently arranged by (re-applied when the canvas changes).
    enum Arrangement: Equatable { case builtIn(Layout), saved(UUID), manual }

    /// A screenshot (image) or a text layer (text); position and size are fractions of the canvas.
    struct Layer: Identifiable {
        var id = UUID()
        var image: CGImage?
        var text: TextStyle?
        var textSize = CGSize(width: 1, height: 1) // natural size of the text, in canvas px
        var center = CGPoint(x: 0.5, y: 0.5)
        var width = 0.5      // fraction of canvas width
        var rotation = 0.0   // degrees
        var corner = 0.03    // radius as a fraction of the layer's width (screenshots)
        var isSample = false // part of the first-run example
        var isText: Bool { text != nil }
    }

    struct Slot: Codable { var x, y, width, rotation, corner: Double }
    struct SavedLayout: Codable, Identifiable {
        var id = UUID()
        var name: String
        var slots: [Slot]
    }

    var layers: [Layer] = []
    var selected: UUID?
    var arrangement = Arrangement.builtIn(.hero)
    var seed: UInt64 = 7
    var width = 1920.0
    var height = 1080.0
    var frame = Frame.window
    var darkChrome = false
    var shadow = 0.7
    var background = Background.mesh
    var bgColor = Color(white: 0.95)
    var bgImage: CGImage?
    var bgBlur = 0.0
    var trim = false
    let mesh = MeshModel()
    var showsSample: Bool { layers.contains(where: \.isSample) }

    init() { loadSample() }

    /// A ready-made composition so first-time users see what Showcase does.
    func loadSample() {
        layers = ShowcaseSamples.images.map { Layer(image: $0, corner: Self.corner(for: $0), isSample: true) }
        var headline = TextStyle()
        headline.text = "Ship it beautifully."
        var sub = TextStyle()
        sub.text = "Compose screenshots, type and gradients in seconds."
        sub.member = "AvenirNext-Medium"; sub.size = 40; sub.tracking = 0; sub.color1 = .white.opacity(0.78)
        for style in [headline, sub] {
            var t = Layer(text: style, isSample: true)
            t.textSize = TextArt.measure(style)
            t.width = t.textSize.width / width
            layers.append(t)
        }
        arrange(.hero)
        selected = nil
    }

    /// Phones get phone-like rounding; desktop/web shots get a subtle window radius.
    static func corner(for img: CGImage) -> Double { img.height > img.width ? 0.11 : 0.018 }

    /// Window chrome (traffic lights) only makes sense on landscape, desktop-style shots.
    func hasChrome(_ img: CGImage) -> Bool { frame != .none && img.height < img.width }

    func clearSample() {
        layers.removeAll(where: \.isSample)
        selected = layers.last?.id
    }
    var saved: [SavedLayout] = ShowcaseModel.loadSaved() { didSet { persist() } }

    var barRatio: Double { frame == .none ? 0 : 0.045 }
    /// Layer height as a fraction of its own width.
    func aspect(_ l: Layer) -> Double {
        if let img = l.image { return Double(img.height) / Double(img.width) + (hasChrome(img) ? barRatio : 0) }
        return l.textSize.height / l.textSize.width
    }
    var selectedIndex: Int? { layers.firstIndex { $0.id == selected } }

    // MARK: Layers

    func add(_ images: [CGImage]) {
        guard !images.isEmpty else { return }
        if showsSample { clearSample() } // your screenshots replace the example
        // New screenshots go below existing text so headlines stay on top.
        let firstText = layers.firstIndex(where: \.isText) ?? layers.count
        layers.insert(contentsOf: images.map { Layer(image: $0, corner: Self.corner(for: $0)) }, at: firstText)
        relayout()
        selected = layers[firstText + images.count - 1].id
    }

    func addText() {
        var l = Layer(text: TextStyle())
        l.textSize = TextArt.measure(l.text!)
        l.width = min(0.9, l.textSize.width / width)
        l.center = CGPoint(x: 0.5, y: layers.contains { !$0.isText } ? 0.14 : 0.5)
        layers.append(l)
        selected = l.id
        relayout() // new text joins the layout's text block
    }

    /// Applies an edited text style, keeping the on-canvas scale the user chose.
    func setText(_ s: TextStyle, at i: Int) {
        let scale = layers[i].width * width / layers[i].textSize.width
        layers[i].text = s
        layers[i].textSize = TextArt.measure(s)
        layers[i].width = layers[i].textSize.width * scale / width
        if case .builtIn = arrangement { relayout() }
    }

    func reorder(_ op: Order) {
        guard let i = selectedIndex else { return }
        let l = layers.remove(at: i)
        let j = switch op {
        case .front: layers.count
        case .back: 0
        case .forward: min(i + 1, layers.count)
        case .backward: max(i - 1, 0)
        }
        layers.insert(l, at: j)
    }

    func duplicate() {
        guard let i = selectedIndex else { return }
        var copy = layers[i]
        copy.id = UUID()
        copy.center.x += 0.04
        copy.center.y += 0.04
        layers.insert(copy, at: i + 1)
        selected = copy.id
    }

    func delete() {
        layers.removeAll { $0.id == selected }
        selected = layers.last?.id
    }

    // MARK: Arrangements

    func arrange(_ l: Layout) {
        arrangement = .builtIn(l)
        layers = arranged(l)
    }

    func apply(_ s: SavedLayout) {
        arrangement = .saved(s.id)
        layers = arranged(s)
    }

    func relayout() {
        switch arrangement {
        case .builtIn(let l): arrange(l)
        case .saved(let id): if let s = saved.first(where: { $0.id == id }) { apply(s) } else { arrange(.cascade) }
        case .manual: break
        }
    }

    func shuffle() {
        seed &+= 1
        arrange(.scatter)
    }

    /// Designer layout engine: reserves a text zone (headline + subheadline stacked with clear hierarchy),
    /// builds the screenshot group at a consistent scale, then fits the whole group into the remaining
    /// area with even safe margins. Also feeds the live thumbnails, so it must stay pure.
    func arranged(_ layout: Layout) -> [Layer] {
        var out = layers
        let W = width, H = height, m = 0.07 * min(W, H)
        let shots = out.indices.filter { !out[$0].isText }
        let texts = out.indices.filter { out[$0].isText }
        let split = layout == .split && !shots.isEmpty
        var area = CGRect(x: m, y: m, width: W - 2 * m, height: H - 2 * m)

        // 1. Text block: stacked in z-order, centred on top (or left-aligned in a column for Split).
        if !texts.isEmpty {
            let colW = split ? area.width * 0.4 : area.width * 0.84
            var ws = texts.map { min(out[$0].width * W, colW) }
            var hs = zip(texts, ws).map { $1 * aspect(out[$0]) }
            let gap = H * 0.02
            var block = hs.reduce(0, +) + gap * Double(texts.count - 1)
            let maxBlock = split ? area.height : H * 0.3
            if block > maxBlock {
                let k = maxBlock / block
                ws = ws.map { $0 * k }; hs = hs.map { $0 * k }; block = maxBlock
            }
            var y = split ? (H - block) / 2 : m
            for (j, i) in texts.enumerated() {
                out[i].width = ws[j] / W
                out[i].rotation = 0
                out[i].text?.align = split ? .leading : .center
                out[i].center = CGPoint(x: (split ? m + ws[j] / 2 : W / 2) / W, y: (y + hs[j] / 2) / H)
                y += hs[j] + gap
            }
            if split {
                let left = m + colW + m * 0.8
                area = CGRect(x: left, y: m, width: W - left - m, height: H - 2 * m)
            } else if !shots.isEmpty {
                let top = m + block + H * 0.055
                area = CGRect(x: m, y: top, width: W - 2 * m, height: H - top - m)
            }
        }
        guard !shots.isEmpty else { return out }

        // 2. Build the group in abstract units (height 1 = a hero-sized device).
        struct Item { var k: Int; var x, y, h, rot: Double }
        let n = shots.count
        let asp = shots.map { aspect(out[$0]) }          // height ÷ width
        func w(_ it: Item) -> Double { it.h / asp[it.k] }
        let landscape = (0..<n).filter { asp[$0] < 1 }
        var items: [Item] = []
        var order = Array(0..<n)                          // back → front
        var rng = SplitMix(seed: seed)

        switch layout {
        case .hero, .split:
            if let p = landscape.first {
                // Desktop as the anchor; phones overlap its lower corners, bottoms aligned below it.
                items.append(Item(k: p, x: 0, y: 0, h: 1, rot: 0))
                let pw = 1 / asp[p]
                let others = (0..<n).filter { $0 != p }
                for (j, k) in others.enumerated() {
                    let tier = Double(j / 2), side: Double = j % 2 == 0 ? 1 : -1
                    let h = 0.8 * (1 - 0.08 * tier), pwk = h / asp[k]
                    items.append(Item(k: k, x: side * (pw / 2 - pwk * 0.12 + tier * pwk * 0.6), y: 0.5 + 0.08 - h / 2, h: h, rot: 0))
                }
                order = [p] + others.reversed()
            } else {
                // All phones: the middle one leads, the rest tuck in behind at either side.
                let c = n / 2
                let cw = 1 / asp[c]
                items.append(Item(k: c, x: 0, y: 0, h: 1, rot: 0))
                let others = (0..<n).filter { $0 != c }
                for (j, k) in others.enumerated() {
                    let tier = Double(j / 2 + 1), side: Double = j % 2 == 0 ? 1 : -1
                    let h = 1 - 0.12 * tier
                    items.append(Item(k: k, x: side * cw * 0.62 * tier, y: 0.04 * tier, h: h, rot: 0))
                }
                order = others.reversed() + [c]
            }
        case .row:
            var x = 0.0
            for k in 0..<n {
                let it = Item(k: k, x: 0, y: 0, h: 1, rot: 0)
                items.append(Item(k: k, x: x + w(it) / 2, y: 0, h: 1, rot: 0))
                x += w(it) + 0.08
            }
        case .cascade, .bleed:
            let step = (0..<n).map { 1 / asp[$0] }.reduce(0, +) / Double(n) * 0.3
            for k in 0..<n {
                items.append(Item(k: k, x: Double(k) * step, y: Double(k) * 0.14, h: 1, rot: layout == .bleed ? -8 : 0))
            }
        case .fan:
            let spread = n == 1 ? 0 : min(8.0 + 3 * Double(n - 2), 20) * .pi / 180
            let r = 2.8
            for k in 0..<n {
                let t = n == 1 ? 0 : Double(k) / Double(n - 1) * 2 - 1
                let a = t * spread
                items.append(Item(k: k, x: r * sin(a), y: r * (1 - cos(a)), h: 1, rot: a * 180 / .pi))
            }
            order = (0..<n).sorted { abs(Double($0) - Double(n - 1) / 2) > abs(Double($1) - Double(n - 1) / 2) }
        case .stack:
            for k in 0..<n {
                let d = Double(n - 1 - k)
                items.append(Item(k: k, x: -0.16 * d, y: -0.1 * d, h: pow(0.88, d), rot: 0)) // each card peeks out up-left
            }
        case .scatter:
            for k in 0..<n {
                items.append(Item(k: k, x: rng.next(-1.2...1.2), y: rng.next(-0.6...0.6), h: 1, rot: rng.next(-12...12)))
            }
        }

        // 3. Fit the group's rotated bounding box into the area (Bleed deliberately overflows bottom-right).
        var lo = CGPoint(x: Double.infinity, y: Double.infinity), hi = CGPoint(x: -Double.infinity, y: -Double.infinity)
        for it in items {
            let r = it.rot * .pi / 180, iw = w(it)
            let hx = (iw * abs(cos(r)) + it.h * abs(sin(r))) / 2, hy = (iw * abs(sin(r)) + it.h * abs(cos(r))) / 2
            lo = CGPoint(x: min(lo.x, it.x - hx), y: min(lo.y, it.y - hy))
            hi = CGPoint(x: max(hi.x, it.x + hx), y: max(hi.y, it.y + hy))
        }
        let target = layout == .bleed
            ? CGRect(x: area.minX + area.width * 0.2, y: area.minY + area.height * 0.08, width: area.width * 1.0, height: area.height * 1.45)
            : area.insetBy(dx: area.width * 0.02, dy: area.height * 0.02)
        let bw = hi.x - lo.x, bh = hi.y - lo.y
        let k = min(target.width / bw, target.height / bh)
        let tx = target.midX - (lo.x + bw / 2) * k, ty = target.midY - (lo.y + bh / 2) * k
        for it in items {
            let i = shots[it.k]
            out[i].center = CGPoint(x: (it.x * k + tx) / W, y: (it.y * k + ty) / H)
            out[i].width = w(it) * k / W
            out[i].rotation = it.rot
        }

        // 4. Stacking order for this layout (text keeps its slots, so it stays on top).
        let restacked = order.map { out[shots[$0]] }
        for (slot, layer) in zip(shots, restacked) { out[slot] = layer }
        return out
    }

    /// A saved layout mapped onto the current screenshots, in stacking order; extras fall back to Cascade.
    func arranged(_ s: SavedLayout) -> [Layer] {
        var out = arranged(.cascade)
        for (k, i) in out.indices.filter({ !out[$0].isText }).enumerated() where k < s.slots.count {
            let slot = s.slots[k]
            out[i].center = CGPoint(x: slot.x, y: slot.y)
            out[i].width = slot.width
            out[i].rotation = slot.rotation
            out[i].corner = slot.corner
        }
        return out
    }

    func saveCurrent(as name: String) {
        let slots = layers.filter { !$0.isText }.map { Slot(x: $0.center.x, y: $0.center.y, width: $0.width, rotation: $0.rotation, corner: $0.corner) }
        let layout = SavedLayout(name: name.isEmpty ? "Layout \(saved.count + 1)" : name, slots: slots)
        saved.append(layout)
        arrangement = .saved(layout.id)
    }

    private static let storeURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Zemy", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("showcase-layouts.json")
        // Carry saved layouts over from the app's previous name.
        let legacy = support.appendingPathComponent("Prism/showcase-layouts.json")
        if !FileManager.default.fileExists(atPath: url.path) { try? FileManager.default.copyItem(at: legacy, to: url) }
        return url
    }()

    private static func loadSaved() -> [SavedLayout] {
        (try? Data(contentsOf: storeURL)).flatMap { try? JSONDecoder().decode([SavedLayout].self, from: $0) } ?? []
    }

    private func persist() {
        try? JSONEncoder().encode(saved).write(to: Self.storeURL)
    }
}

/// Small deterministic RNG so Scatter thumbnails match what gets applied.
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next(_ r: ClosedRange<Double>) -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return r.lowerBound + Double(z >> 11) / Double(1 << 53) * (r.upperBound - r.lowerBound)
    }
}

// MARK: - Artwork

/// A screenshot with optional window / browser chrome, rounded corners and shadow.
struct ShotView: View {
    let image: CGImage
    let corner: Double
    let m: ShowcaseModel
    let width: CGFloat

    var body: some View {
        let r = width * corner
        VStack(spacing: 0) {
            if m.hasChrome(image) { ChromeBar(m: m, height: width * m.barRatio) }
            Image(decorative: image, scale: 1).resizable().interpolation(.high)
                .frame(width: width, height: width * CGFloat(image.height) / CGFloat(image.width))
        }
        .frame(width: width)
        .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: r, style: .continuous).strokeBorder(.black.opacity(0.1), lineWidth: max(0.5, width * 0.0012)))
        .shadow(color: .black.opacity(0.38 * m.shadow), radius: width * 0.05 * m.shadow, y: width * 0.03 * m.shadow)
    }
}

private struct ChromeBar: View {
    let m: ShowcaseModel
    let height: CGFloat
    var body: some View {
        let dark = m.darkChrome
        ZStack {
            dark ? Color(white: 0.16) : Color(white: 0.93)
            HStack(spacing: height * 0.22) {
                ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18), Color(red: 0.16, green: 0.79, blue: 0.25)], id: \.self) {
                    Circle().fill($0).frame(width: height * 0.34, height: height * 0.34)
                }
            }
            .padding(.leading, height * 0.42)
            .frame(maxWidth: .infinity, alignment: .leading)
            if m.frame == .browser {
                Capsule().fill(dark ? Color(white: 0.09) : .white)
                    .frame(height: height * 0.56)
                    .padding(.horizontal, height * 3.2)
            }
        }
        .frame(height: height)
    }
}

struct ShowcaseArt: View {
    let m: ShowcaseModel
    var layers: [ShowcaseModel.Layer]? = nil

    var body: some View {
        ZStack {
            background
            ForEach(layers ?? m.layers) { l in
                let w = l.width * m.width
                Group {
                    if let style = l.text {
                        // Vector text scaled to the layer's width, so it stays crisp at any size.
                        TextArt(style: style).fixedSize()
                            .scaleEffect(w / l.textSize.width)
                            .frame(width: w, height: w * m.aspect(l))
                    } else if let img = l.image {
                        ShotView(image: img, corner: l.corner, m: m, width: w)
                    }
                }
                .rotationEffect(.degrees(l.rotation))
                .position(x: l.center.x * m.width, y: l.center.y * m.height)
            }
        }
        .frame(width: m.width, height: m.height)
        .clipped()
    }

    @ViewBuilder private var background: some View {
        switch m.background {
        case .none: Color.clear
        case .color: m.bgColor
        case .mesh: MeshArt(m: m.mesh)
        case .image:
            if let bg = m.bgImage {
                Image(decorative: bg, scale: 1).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: m.width, height: m.height)
                    .blur(radius: m.bgBlur)
                    .scaleEffect(1 + m.bgBlur / 300) // hide soft blurred edges
                    .clipped()
            } else {
                Color.gray.opacity(0.2)
            }
        }
    }

    @MainActor static func render(_ m: ShowcaseModel) -> CGImage? {
        let r = ImageRenderer(content: ShowcaseArt(m: m))
        r.scale = 1
        guard let img = r.cgImage else { return nil }
        return m.trim && m.background == .none ? img.trimmedToContent() : img
    }
}

private extension CGImage {
    /// Crops away fully transparent edges.
    func trimmedToContent() -> CGImage {
        let px = rgba()
        var minX = width, minY = height, maxX = -1, maxY = -1
        px.data.withUnsafeBufferPointer { p in
            for y in 0..<height {
                for x in 0..<width where p[(y * width + x) * 4 + 3] > 8 {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= minX else { return self }
        return cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) ?? self
    }
}

// MARK: - Editing overlay (select, move, resize)

private struct ShowcaseEditor: View {
    let m: ShowcaseModel
    let k: CGFloat
    @State private var origin: CGPoint?
    @State private var originWidth: Double?

    var body: some View {
        let W = m.width * k, H = m.height * k
        ZStack {
            Color.clear.contentShape(Rectangle()).onTapGesture { m.selected = nil }
            ForEach(m.layers) { l in
                let w = l.width * W, h = w * m.aspect(l)
                let selected = m.selected == l.id
                Rectangle().fill(Color.white.opacity(0.001))
                    .frame(width: w, height: h)
                    .contentShape(Rectangle())
                    .overlay {
                        if selected {
                            RoundedRectangle(cornerRadius: l.isText ? 4 : w * l.corner, style: .continuous)
                                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: l.isText ? [6, 4] : []))
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if selected {
                            Circle().fill(.white).frame(width: 16, height: 16)
                                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
                                .padding(6).contentShape(Circle()) // bigger grab target
                                .offset(x: 14, y: 14)
                                .onHover { $0 ? NSCursor.crosshair.push() : NSCursor.pop() }
                                .gesture(DragGesture(coordinateSpace: .named("showcase"))
                                    .onChanged { v in
                                        if originWidth == nil { originWidth = l.width }
                                        update(l.id) { $0.width = max(0.03, originWidth! + v.translation.width * 2 / W) }
                                    }
                                    .onEnded { _ in originWidth = nil })
                        }
                    }
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("showcase"))
                        .onChanged { v in
                            m.selected = l.id
                            if origin == nil { origin = l.center }
                            update(l.id) { $0.center = CGPoint(x: origin!.x + v.translation.width / W, y: origin!.y + v.translation.height / H) }
                        }
                        .onEnded { _ in origin = nil })
                    .onTapGesture { m.selected = l.id }
                    .rotationEffect(.degrees(l.rotation))
                    .position(x: l.center.x * W, y: l.center.y * H)
            }
        }
        .frame(width: W, height: H)
        .coordinateSpace(name: "showcase")
    }

    private func update(_ id: UUID, _ change: (inout ShowcaseModel.Layer) -> Void) {
        guard let i = m.layers.firstIndex(where: { $0.id == id }) else { return }
        change(&m.layers[i])
        m.arrangement = .manual
    }
}

// MARK: - Tool view

struct ShowcaseToolView: View {
    @Bindable var model: ShowcaseModel
    @Environment(AppState.self) private var state
    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        ToolScaffold(tool: .showcase) {
            if model.layers.isEmpty {
                DropZone(tool: .showcase, extra: AnyView(HStack {
                    Button { model.addText() } label: { Label("Add Text", systemImage: "textformat") }
                    Button { model.loadSample() } label: { Label("Show Example", systemImage: "sparkles") }
                })) { state.open($0) }
            } else {
                ZoomCanvas(size: CGSize(width: model.width, height: model.height), checker: model.background == .none, pannable: false) { k in
                    ShowcaseArt(m: model).scaleEffect(k, anchor: .topLeading)
                        .frame(width: model.width * k, height: model.height * k, alignment: .topLeading)
                        .overlay { ShowcaseEditor(m: model, k: k) }
                }
                .onDeleteCommand { model.delete() }
                .imageDrop { state.open($0) }
                .overlay(alignment: .top) { if model.showsSample { sampleBar } }
            }
        } inspector: {
            layersPanel
            Panel(title: "Canvas", symbol: "rectangle.dashed") {
                CanvasSizePicker(width: $model.width, height: $model.height)
            }
            if let i = model.selectedIndex, model.layers[i].isText {
                TextStylePanels(style: Binding(get: { model.layers[i].text! }, set: { model.setText($0, at: i) }))
            }
            if model.layers.contains(where: { !$0.isText }) { layoutsPanel }
            Panel(title: "Screenshot Style", symbol: "macwindow") {
                Picker("Frame", selection: $model.frame) { ForEach(ShowcaseModel.Frame.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                if model.frame != .none { Toggle("Dark window chrome", isOn: $model.darkChrome) }
                SliderRow(label: "Shadow", value: $model.shadow, range: 0...1.5) { "\(Int($0 * 100))%" }
            }
            Panel(title: "Background", symbol: "square.3.layers.3d") {
                Picker("Background", selection: $model.background) { ForEach(ShowcaseModel.Background.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden()
                switch model.background {
                case .none:
                    Text("Transparent — exports as PNG with alpha.").font(.caption).foregroundStyle(.secondary)
                    Toggle("Trim to content on export", isOn: $model.trim)
                case .color: ColorPicker("Color", selection: $model.bgColor)
                case .mesh: MeshPanel(m: model.mesh)
                case .image:
                    HStack {
                        Button("Choose Image…") {
                            if let u = Inbox.openPanel(multiple: false, types: [.image]).first, let d = try? Data(contentsOf: u) {
                                model.bgImage = ImageIOKit.load(d)?.image
                            }
                        }
                        Button("Use Working Image") { model.bgImage = state.current?.image }.disabled(state.current == nil)
                    }
                    SliderRow(label: "Blur", value: $model.bgBlur, range: 0...80)
                }
            }
            ExportPanel(id: "showcase", name: CanvasPresets.match(model.width, model.height)?.fileName ?? "Showcase",
                        formats: [.png, .jpeg, .webp, .heic, .avif, .tiff]) { _ in ShowcaseArt.render(model) }
        }
        .toolbar {
            Button { model.addText() } label: { Label("Add Text", systemImage: "textformat") }.help("Add a text layer")
        }
        .onChange(of: model.width) { model.relayout() }
        .onChange(of: model.height) { model.relayout() }
        .onChange(of: model.frame) { model.relayout() }
    }

    private var sampleBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").foregroundStyle(Tool.showcase.tint)
            Text("Example — drop, paste or add your screenshots to replace it").font(.callout)
            Button("Add Screenshots…") { state.open(Inbox.openPanel()) }.buttonStyle(.borderedProminent).tint(Tool.showcase.tint)
            Button("Clear Sample") { model.clearSample() }
        }
        .controlSize(.small)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .padding(.top, 12)
    }

    // MARK: Panels

    private var layersPanel: some View {
        Panel(title: "Screenshots & Text", symbol: "photo.stack") {
            HStack {
                Button { state.open(Inbox.openPanel()) } label: { Label("Add…", systemImage: "plus") }
                Button { state.paste() } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                Button { model.addText() } label: { Label("Text", systemImage: "textformat") }
            }
            if !model.layers.isEmpty { layerStrip }
            if let i = model.selectedIndex {
                HStack(spacing: 4) {
                    orderButton("square.3.layers.3d.top.filled", "Bring to front", .front)
                    orderButton("square.2.layers.3d.top.filled", "Bring forward", .forward)
                    orderButton("square.2.layers.3d.bottom.filled", "Send backward", .backward)
                    orderButton("square.3.layers.3d.bottom.filled", "Send to back", .back)
                    Spacer()
                    Button { model.duplicate() } label: { Image(systemName: "plus.square.on.square") }.help("Duplicate")
                    Button(role: .destructive) { model.delete() } label: { Image(systemName: "trash") }.help("Delete (⌫)")
                }
                SliderRow(label: "Size", value: $model.layers[i].width, range: 0.03...1.2) { "\(Int($0 * 100))%" }
                SliderRow(label: "Rotation", value: $model.layers[i].rotation, range: -30...30) { "\(Int($0))°" }
                if !model.layers[i].isText {
                    let px = model.layers[i].width * model.width
                    SliderRow(label: "Corner radius", value: $model.layers[i].corner, range: 0...0.15) { "\(Int($0 * px)) px" }
                    Button("Apply this radius to all") {
                        let r = model.layers[i].corner
                        for j in model.layers.indices { model.layers[j].corner = r }
                    }
                    .controlSize(.small).disabled(model.layers.filter { !$0.isText }.count < 2)
                }
            }
            Text("Click to select, drag to move, drag the corner dot to resize.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var layoutsPanel: some View {
        Panel(title: "Layouts", symbol: "rectangle.3.group") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 10) {
                ForEach(ShowcaseModel.Layout.allCases) { layout in
                    thumbnail(layout.rawValue, layers: model.arranged(layout), on: model.arrangement == .builtIn(layout)) { model.arrange(layout) }
                }
            }
            Button { withAnimation(.snappy) { model.shuffle() } } label: { Label("Shuffle Scatter", systemImage: "dice").frame(maxWidth: .infinity) }
            if !model.saved.isEmpty {
                Text("My Layouts").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 10) {
                    ForEach(model.saved) { s in
                        thumbnail(s.name, layers: model.arranged(s), on: model.arrangement == .saved(s.id)) { model.apply(s) }
                            .contextMenu { Button("Delete Layout", role: .destructive) { model.saved.removeAll { $0.id == s.id } } }
                    }
                }
            }
            Button { newName = ""; naming = true } label: {
                Label("Save Arrangement…", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
            }
            .popover(isPresented: $naming, arrowEdge: .leading) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Save this arrangement").font(.headline)
                    TextField("Name, e.g. Dribbble trio", text: $newName).textFieldStyle(.roundedBorder).frame(width: 220)
                        .onSubmit { model.saveCurrent(as: newName); naming = false }
                    HStack {
                        Spacer()
                        Button("Cancel") { naming = false }
                        Button("Save") { model.saveCurrent(as: newName); naming = false }.buttonStyle(.borderedProminent)
                    }
                }
                .padding(14)
            }
            Text("Saved layouts remember screenshot positions, sizes, rotation and corners, and work with any new shots.")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var layerStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(model.layers.reversed()) { l in
                    Group {
                        if let img = l.image {
                            Image(decorative: img, scale: 1).resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: "textformat").font(.title3).frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(.quaternary)
                        }
                    }
                    .frame(width: 46, height: 46).clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(model.selected == l.id ? Color.accentColor : .clear, lineWidth: 2.5))
                    .onTapGesture { model.selected = l.id }
                    .help(l.text?.text ?? "Screenshot")
                }
            }
            .padding(2)
        }
        .scrollIndicators(.hidden)
    }

    private func orderButton(_ symbol: String, _ help: String, _ op: ShowcaseModel.Order) -> some View {
        Button { withAnimation(.snappy) { model.reorder(op) } } label: { Image(systemName: symbol) }.help(help)
    }

    private func thumbnail(_ title: String, layers: [ShowcaseModel.Layer], on: Bool, apply: @escaping () -> Void) -> some View {
        let w: CGFloat = 126, s = w / model.width
        return Button { withAnimation(.snappy) { apply() } } label: {
            VStack(spacing: 4) {
                ShowcaseArt(m: model, layers: layers)
                    .scaleEffect(s, anchor: .topLeading)
                    .frame(width: w, height: model.height * s, alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(on ? Color.accentColor : .primary.opacity(0.12), lineWidth: on ? 2.5 : 1))
                Text(title).font(.caption).foregroundStyle(on ? .primary : .secondary).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}
