import SwiftUI
import UniformTypeIdentifiers

// MARK: - Devices, styles, languages

/// App Store Connect screenshot sizes (portrait) for iPhone and iPad.
enum StoreDevice: String, CaseIterable, Identifiable {
    case iphone69 = "iPhone 6.9″", iphone63 = "iPhone 6.3″", ipad13 = "iPad 13″"
    var id: Self { self }
    var size: CGSize {
        switch self {
        case .iphone69: CGSize(width: 1320, height: 2868)
        case .iphone63: CGSize(width: 1206, height: 2622)
        case .ipad13: CGSize(width: 2064, height: 2752)
        }
    }
    var isPad: Bool { self == .ipad13 }
    var folder: String { "\(rawValue.replacingOccurrences(of: "″", with: "in")) \(Int(size.width))x\(Int(size.height))" }
}

enum StoreStyle: String, CaseIterable, Identifiable {
    case captionTop = "Caption top", captionBottom = "Caption bottom", noText = "No text", tilted = "Tilted",
         duo = "Duo", panorama = "Panorama", spotlight = "Spotlight"
    var id: Self { self }
}

enum StoreBackground: String, CaseIterable, Identifiable {
    case mesh = "Mesh", gradient = "Gradient", color = "Color", image = "Image"
    var id: Self { self }
}

/// App Store Connect localizations.
enum StoreLocales {
    static let all: [(code: String, name: String)] = [
        ("en-US", "English (U.S.)"), ("en-GB", "English (U.K.)"), ("en-AU", "English (Australia)"), ("en-CA", "English (Canada)"),
        ("fr-FR", "French"), ("fr-CA", "French (Canada)"), ("de-DE", "German"), ("es-ES", "Spanish (Spain)"),
        ("es-MX", "Spanish (Mexico)"), ("it", "Italian"), ("pt-BR", "Portuguese (Brazil)"), ("pt-PT", "Portuguese (Portugal)"),
        ("nl-NL", "Dutch"), ("sv", "Swedish"), ("da", "Danish"), ("no", "Norwegian"), ("fi", "Finnish"), ("pl", "Polish"),
        ("cs", "Czech"), ("tr", "Turkish"), ("ru", "Russian"), ("uk", "Ukrainian"), ("ar-SA", "Arabic"), ("he", "Hebrew"),
        ("hi", "Hindi"), ("th", "Thai"), ("vi", "Vietnamese"), ("id", "Indonesian"), ("ms", "Malay"), ("ja", "Japanese"),
        ("ko", "Korean"), ("zh-Hans", "Chinese (Simplified)"), ("zh-Hant", "Chinese (Traditional)"),
    ]
    static func name(_ code: String) -> String { all.first { $0.code == code }?.name ?? code }
    static func isRTL(_ code: String) -> Bool { code.hasPrefix("ar") || code.hasPrefix("he") }
}

// MARK: - Model

@MainActor @Observable
final class StoreModel {
    struct Caption: Equatable { var headline = "", sub = "" }
    struct Page: Identifiable {
        let id = UUID()
        var phone: CGImage?
        var pad: CGImage?
        var captions: [String: Caption] = [:]
        var isSample = false
    }
    struct Issue: Identifiable { let id = UUID(); let error: Bool; let text: String }

    var pages: [Page] = []
    var selected: UUID?
    var device = StoreDevice.iphone69
    var exportDevices: Set<StoreDevice> = Set(StoreDevice.allCases)
    var style = StoreStyle.captionTop
    var showText = true
    var showSub = true
    var framed = true
    var finish = DeviceFrame.Finish.black
    var shadow = 0.6
    var headline: TextStyle = {
        var s = TextStyle()
        s.member = "AvenirNext-Bold"; s.size = 104; s.tracking = -1; s.color1 = .white
        return s
    }()
    var subSize = 54.0
    var subColor = Color.white.opacity(0.82)
    var background = StoreBackground.mesh
    var bg1 = Color(red: 0.36, green: 0.33, blue: 0.95)
    var bg2 = Color(red: 0.08, green: 0.06, blue: 0.2)
    var bgImage: CGImage?
    let mesh = MeshModel()
    var spotY = 0.35
    var locales = ["en-US"]
    var locale = "en-US"
    var format = ImageFormat.png
    var progress: Double?
    var message: String?

    var primary: String { locales[0] }
    var selectedIndex: Int? { pages.firstIndex { $0.id == selected } }
    var showsSample: Bool { pages.contains(where: \.isSample) }

    init() { loadSample() }

    func loadSample() {
        let shots = ShowcaseSamples.images
        guard shots.count >= 2 else { return }
        pages = [
            Page(phone: shots[0], pad: ShowcaseSamples.padDashboard,
                 captions: ["en-US": Caption(headline: "Music that moves with you", sub: "Beautiful playback on every device")], isSample: true),
            Page(phone: shots[1], pad: ShowcaseSamples.padDashboard,
                 captions: ["en-US": Caption(headline: "Plan your day in seconds", sub: "Smart lists that stay out of your way")], isSample: true),
        ]
        selected = pages.first?.id
    }

    /// Tall images become iPhone pages; iPad-shaped ones fill the first page still missing an iPad shot.
    func add(_ images: [CGImage]) {
        guard !images.isEmpty else { return }
        if showsSample { pages.removeAll(where: \.isSample) }
        for img in images {
            if Double(img.height) / Double(img.width) >= 1.6 {
                pages.append(Page(phone: img))
            } else if let i = pages.firstIndex(where: { $0.pad == nil }) {
                pages[i].pad = img
            } else {
                pages.append(Page(pad: img))
            }
        }
        selected = selected ?? pages.first?.id
    }

    func image(_ i: Int, _ d: StoreDevice) -> CGImage? {
        guard pages.indices.contains(i) else { return nil }
        return d.isPad ? (pages[i].pad ?? pages[i].phone) : (pages[i].phone ?? pages[i].pad)
    }

    func move(_ i: Int, by delta: Int) {
        let j = i + delta
        guard pages.indices.contains(j) else { return }
        pages.swapAt(i, j)
    }

    // MARK: Captions & languages

    /// Falls back to the primary language so previews never go blank while translating.
    func caption(_ i: Int, _ loc: String) -> Caption {
        guard pages.indices.contains(i) else { return Caption() }
        if let c = pages[i].captions[loc], !(c.headline.isEmpty && c.sub.isEmpty) { return c }
        return pages[i].captions[primary] ?? Caption()
    }

    func missing(_ loc: String) -> Int {
        guard loc != primary else { return 0 }
        return pages.indices.filter { i in
            let p = pages[i].captions[primary] ?? Caption()
            let c = pages[i].captions[loc] ?? Caption()
            return (!p.headline.isEmpty && c.headline.isEmpty) || (!p.sub.isEmpty && c.sub.isEmpty)
        }.count
    }

    func addLocale(_ code: String) {
        guard !locales.contains(code) else { return }
        locales.append(code)
        locale = code
    }

    func removeLocale(_ code: String) {
        guard code != primary else { return }
        locales.removeAll { $0 == code }
        for i in pages.indices { pages[i].captions[code] = nil }
        if locale == code { locale = primary }
    }

    /// page,locale,headline,subheadline — one row per page per language, ready for translators.
    var csv: String {
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var rows = ["page,locale,headline,subheadline"]
        for loc in locales {
            for i in pages.indices {
                let c = pages[i].captions[loc] ?? Caption()
                rows.append("\(i + 1),\(loc),\(q(c.headline)),\(q(c.sub))")
            }
        }
        return rows.joined(separator: "\n")
    }

    func importCSV(_ text: String) -> Int {
        var count = 0
        for row in Self.parseCSV(text).dropFirst() where row.count >= 3 {
            guard let n = Int(row[0].trimmingCharacters(in: .whitespaces)), pages.indices.contains(n - 1) else { continue }
            let loc = row[1].trimmingCharacters(in: .whitespaces)
            guard !loc.isEmpty else { continue }
            if !locales.contains(loc) { locales.append(loc) }
            pages[n - 1].captions[loc] = Caption(headline: row[2], sub: row.count > 3 ? row[3] : "")
            count += 1
        }
        return count
    }

    static func parseCSV(_ s: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { quoted = false }
                } else { field.append(c) }
            } else {
                switch c {
                case "\"": quoted = true
                case ",": row.append(field); field = ""
                case "\n", "\r\n": row.append(field); rows.append(row); row = []; field = ""
                case "\r": break
                default: field.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    // MARK: Validation & export

    var issues: [Issue] {
        var out: [Issue] = []
        if pages.isEmpty { out.append(Issue(error: true, text: "Add at least one screenshot.")) }
        if pages.count > 10 { out.append(Issue(error: true, text: "App Store Connect accepts up to 10 screenshots per device size — you have \(pages.count).")) }
        if exportDevices.isEmpty { out.append(Issue(error: true, text: "Choose at least one device size to export.")) }
        if !exportDevices.contains(.iphone63) && !exportDevices.contains(.iphone69) {
            out.append(Issue(error: false, text: "No iPhone set selected. Apple requires iPhone screenshots for iPhone apps (export 6.3″, and 6.9″ to be safe)."))
        }
        if exportDevices.contains(.ipad13) {
            let n = pages.filter { $0.pad == nil }.count
            if n > 0 { out.append(Issue(error: false, text: "\(n) page\(n == 1 ? " has" : "s have") no iPad screenshot; the iPhone screenshot will appear in the iPad frame.")) }
        }
        for loc in locales.dropFirst() where missing(loc) > 0 {
            out.append(Issue(error: false, text: "\(StoreLocales.name(loc)): \(missing(loc)) page\(missing(loc) == 1 ? "" : "s") still use \(StoreLocales.name(primary)) text."))
        }
        return out
    }

    func render(_ i: Int, _ d: StoreDevice, _ loc: String) -> CGImage? {
        let r = ImageRenderer(content: StorePage(m: self, index: i, device: d, locale: loc))
        r.scale = 1
        return r.cgImage
    }

    /// Writes <root>/App Store Screenshots/<locale>/<device>/01.png… — exact pixels, no alpha channel.
    @discardableResult
    func export(to root: URL) async -> URL {
        var base = root.appendingPathComponent("App Store Screenshots"), n = 2
        while FileManager.default.fileExists(atPath: base.path) {
            base = root.appendingPathComponent("App Store Screenshots \(n)"); n += 1
        }
        let devices = StoreDevice.allCases.filter(exportDevices.contains)
        let total = Double(locales.count * devices.count * min(pages.count, 10))
        var done = 0.0
        progress = 0
        let opts = EncodeOptions(format: format, quality: 0.92)
        for loc in locales {
            for d in devices {
                let dir = base.appendingPathComponent(loc).appendingPathComponent(d.folder)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                for i in pages.indices.prefix(10) {
                    if let img = render(i, d, loc), img.width == Int(d.size.width), img.height == Int(d.size.height) {
                        let flat = img.flattened()
                        let data = await Task.detached { Encoder.encode(flat, opts) }.value
                        try? data?.write(to: dir.appendingPathComponent(String(format: "%02d.%@", i + 1, format.ext)))
                    }
                    done += 1
                    progress = done / max(total, 1)
                }
            }
        }
        progress = nil
        message = "Exported \(Int(done)) screenshots (\(locales.count) language\(locales.count == 1 ? "" : "s") × \(devices.count) size\(devices.count == 1 ? "" : "s"))."
        return base
    }
}

// MARK: - Page rendering

/// One App Store screenshot at the device's exact pixel size.
struct StorePage: View {
    let m: StoreModel
    let index: Int
    let device: StoreDevice
    let locale: String
    /// Overrides the model's style (used by the style gallery thumbnails).
    var style: StoreStyle? = nil
    private var st: StoreStyle { style ?? m.style }

    private struct Placed: Identifiable { let id: Int; let image: CGImage?; let center: CGPoint; let width: CGFloat; let rotation: Double }

    var body: some View {
        let W = device.size.width, H = device.size.height
        let cap = m.caption(index, locale)
        let hasText = m.showText && st != .noText && !(cap.headline.isEmpty && (cap.sub.isEmpty || !m.showSub))
        let (devices, textY) = layout(W, H, hasText)
        ZStack {
            background(W, H)
            if st == .spotlight, let first = devices.first { spotlight(first, W) }
            ForEach(devices) { p in
                DeviceFrame(image: p.image, pad: device.isPad, framed: m.framed, finish: m.finish,
                            width: p.width, screenAspect: H / W, shadow: m.shadow)
                    .rotationEffect(.degrees(p.rotation))
                    .position(p.center)
            }
            if st == .spotlight, let first = devices.first { spotlightCard(first, W) }
            if hasText { captionView(cap, W).position(x: W / 2, y: textY) }
        }
        .frame(width: W, height: H)
        .clipped()
    }

    private func layout(_ W: CGFloat, _ H: CGFloat, _ hasText: Bool) -> ([Placed], CGFloat) {
        let a = DeviceFrame.aspect(pad: device.isPad, framed: m.framed, screenAspect: H / W)
        func fit(_ w: CGFloat, _ h: CGFloat) -> CGFloat { min(w * W, h * H / a) }
        let shot = m.image(index, device)
        let flip: CGFloat = index % 2 == 0 ? 1 : -1
        let topText = H * 0.13, bottomText = H * 0.885
        func one(_ w: CGFloat, x: CGFloat = 0.5, top: CGFloat, rot: Double = 0) -> [Placed] {
            [Placed(id: 0, image: shot, center: CGPoint(x: W * x, y: top + w * a / 2), width: w, rotation: rot)]
        }
        switch st {
        case .captionTop:
            let w = fit(0.8, hasText ? 0.74 : 0.88)
            return (one(w, top: hasText ? H * 0.255 : (H - w * a) / 2), topText)
        case .captionBottom:
            let w = fit(0.8, hasText ? 0.74 : 0.88)
            return (one(w, top: hasText ? H * 0.045 : (H - w * a) / 2), bottomText)
        case .noText:
            let w = fit(0.86, 0.9)
            return (one(w, top: (H - w * a) / 2), topText)
        case .tilted:
            let w = fit(0.86, 0.8)
            return (one(w, x: 0.5 + 0.05 * flip, top: hasText ? H * 0.27 : H * 0.12, rot: -8 * flip), topText)
        case .panorama:
            let w = fit(0.76, 0.72)
            return (one(w, x: 0.5 + 0.09 * flip, top: hasText ? H * 0.265 : H * 0.14, rot: 4 * flip), topText)
        case .spotlight:
            let w = fit(0.66, 0.7)
            return (one(w, x: 0.39, top: hasText ? H * 0.27 : (H - w * a) / 2), topText)
        case .duo:
            let w = fit(0.6, 0.62)
            let other = m.pages.count > 1 ? m.image((index + 1) % m.pages.count, device) : shot
            let top = hasText ? H * 0.28 : (H - w * a) / 2
            return ([Placed(id: 1, image: other, center: CGPoint(x: W * 0.33, y: top + w * a / 2 - H * 0.03), width: w, rotation: -4),
                     Placed(id: 0, image: shot, center: CGPoint(x: W * 0.67, y: top + w * a / 2 + H * 0.03), width: w, rotation: 4)], topText)
        }
    }

    // MARK: Pieces

    @ViewBuilder private func background(_ W: CGFloat, _ H: CGFloat) -> some View {
        let wide = st == .panorama
        let n = CGFloat(max(m.pages.count, 1))
        Group {
            switch m.background {
            case .mesh: MeshArt(m: m.mesh)
            case .gradient: LinearGradient(colors: [m.bg1, m.bg2], startPoint: wide ? .leading : .top, endPoint: wide ? .trailing : .bottom)
            case .color: m.bg1
            case .image:
                if let bg = m.bgImage { Image(decorative: bg, scale: 1).resizable().aspectRatio(contentMode: .fill) } else { m.bg1 }
            }
        }
        // Panorama: one continuous background across the whole set, sliced per page.
        .frame(width: wide ? W * n : W, height: H)
        .offset(x: wide ? -W * CGFloat(index) : 0)
        .frame(width: W, height: H, alignment: .leading)
        .clipped()
    }

    private func captionView(_ c: StoreModel.Caption, _ W: CGFloat) -> some View {
        let k = min(W / 1290, 1.3)
        return VStack(spacing: 20 * k) {
            if !c.headline.isEmpty {
                Text(c.headline)
                    .font(.custom(m.headline.member, size: m.headline.size * k))
                    .tracking(m.headline.tracking * k)
                    .foregroundStyle(m.headline.color1)
            }
            if m.showSub && !c.sub.isEmpty {
                Text(c.sub).font(.custom(subMember, size: m.subSize * k)).foregroundStyle(m.subColor)
            }
        }
        .multilineTextAlignment(.center)
        .lineLimit(3)
        .minimumScaleFactor(0.5)
        .frame(width: W * 0.86)
        .environment(\.layoutDirection, StoreLocales.isRTL(locale) ? .rightToLeft : .leftToRight)
    }

    private var subMember: String {
        let ms = Fonts.members(m.headline.family)
        return ms.first { $0.style == "Medium" }?.ps ?? ms.first { $0.style == "Regular" }?.ps ?? m.headline.member
    }

    /// Soft glow behind the device in Spotlight.
    private func spotlight(_ p: Placed, _ W: CGFloat) -> some View {
        Circle().fill(.white.opacity(0.18)).frame(width: W * 0.9).blur(radius: W * 0.08).position(x: W * 0.62, y: p.center.y)
    }

    /// A magnified crop of the screenshot, floating beside the device.
    @ViewBuilder private func spotlightCard(_ p: Placed, _ W: CGFloat) -> some View {
        if let img = p.image {
            let h = CGFloat(img.height) * 0.2, y = max(0, min(CGFloat(img.height) - h, CGFloat(img.height) * m.spotY - h / 2))
            if let crop = img.cropping(to: CGRect(x: 0, y: y, width: CGFloat(img.width), height: h)) {
                let cw = W * 0.58
                Image(decorative: crop, scale: 1).resizable().interpolation(.high)
                    .frame(width: cw, height: cw * h / CGFloat(img.width))
                    .clipShape(RoundedRectangle(cornerRadius: W * 0.03, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: W * 0.03, style: .continuous).strokeBorder(.white, lineWidth: W * 0.008))
                    .shadow(color: .black.opacity(0.35), radius: W * 0.04, y: W * 0.02)
                    .position(x: W * 0.66, y: p.center.y - p.width * 0.15)
            }
        }
    }
}

// MARK: - Tool view

struct AppStoreToolView: View {
    @Bindable var model: StoreModel
    @Environment(AppState.self) private var state

    var body: some View {
        ToolScaffold(tool: .appstore) {
            VStack(spacing: 0) {
                topBar
                if model.pages.isEmpty {
                    DropZone(tool: .appstore, extra: AnyView(Button { model.loadSample() } label: { Label("Show Example", systemImage: "sparkles") })) { state.open($0) }
                } else {
                    pageStrip
                }
            }
            .imageDrop { state.open($0) }
        } inspector: {
            screenshotsPanel
            if let i = model.selectedIndex { pagePanel(i) }
            languagesPanel
            stylePanel
            textPanel
            backgroundPanel
            exportPanel
        }
    }

    // MARK: Canvas

    private var topBar: some View {
        HStack(spacing: 10) {
            Picker("Device", selection: $model.device) {
                ForEach(StoreDevice.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 300)
            Picker("Language", selection: $model.locale) {
                ForEach(model.locales, id: \.self) { Text(StoreLocales.name($0)).tag($0) }
            }
            .labelsHidden().frame(maxWidth: 170)
            Spacer(minLength: 0)
            if model.showsSample {
                Button("Clear Sample") { model.pages.removeAll(); model.selected = nil }.controlSize(.small)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var pageStrip: some View {
        GeometryReader { geo in
            let size = model.device.size
            let s = max(0.05, (geo.size.height - 70) / size.height)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(Array(model.pages.enumerated()), id: \.element.id) { i, page in
                        VStack(spacing: 8) {
                            StorePage(m: model, index: i, device: model.device, locale: model.locale)
                                .scaleEffect(s, anchor: .topLeading)
                                .frame(width: size.width * s, height: size.height * s, alignment: .topLeading)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(model.selected == page.id ? Color.accentColor : .primary.opacity(0.12), lineWidth: model.selected == page.id ? 3 : 1))
                                .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                                .onTapGesture { model.selected = page.id }
                                .contextMenu { pageMenu(i) }
                            HStack(spacing: 4) {
                                Text("\(i + 1)").font(.caption.weight(.semibold))
                                if i == 0 { Text("· \(Int(size.width))×\(Int(size.height)) px").font(.caption).monospacedDigit() }
                                if i >= 10 { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help("Beyond App Store's 10-screenshot limit") }
                                if model.device.isPad && page.pad == nil { Image(systemName: "ipad.slash").foregroundStyle(.orange).help("No iPad screenshot yet") }
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    @ViewBuilder private func pageMenu(_ i: Int) -> some View {
        Button("Move Left") { model.move(i, by: -1) }.disabled(i == 0)
        Button("Move Right") { model.move(i, by: 1) }.disabled(i == model.pages.count - 1)
        Divider()
        Button("Set iPhone Screenshot…") { pick { model.pages[i].phone = $0 } }
        Button("Set iPad Screenshot…") { pick { model.pages[i].pad = $0 } }
        Divider()
        Button("Delete Page", role: .destructive) { model.pages.remove(at: i) }
    }

    private func pick(_ set: (CGImage) -> Void) {
        guard let u = Inbox.openPanel(multiple: false, types: [.image]).first,
              let d = try? Data(contentsOf: u), let img = ImageIOKit.load(d)?.image else { return }
        set(img)
    }

    // MARK: Inspector

    private var screenshotsPanel: some View {
        Panel(title: "Screenshots", symbol: "iphone.and.ipad") {
            HStack {
                Button { state.open(Inbox.openPanel()) } label: { Label("Add…", systemImage: "plus") }
                Button { state.paste() } label: { Label("Paste", systemImage: "doc.on.clipboard") }
            }
            Text("Each iPhone screenshot becomes a page; iPad screenshots attach to pages in order. Right-click a page to reorder or replace shots.")
                .font(.caption).foregroundStyle(.secondary)
            Text("\(model.pages.count) of 10 pages").font(.caption.weight(.medium)).foregroundStyle(model.pages.count > 10 ? .red : .secondary)
        }
    }

    private func pagePanel(_ i: Int) -> some View {
        let primary = model.pages[i].captions[model.primary] ?? .init()
        let editingPrimary = model.locale == model.primary
        return Panel(title: "Page \(i + 1) · \(StoreLocales.name(model.locale))", symbol: "text.below.photo") {
            TextField(editingPrimary ? "Headline" : primary.headline, text: Binding(
                get: { model.pages[i].captions[model.locale]?.headline ?? "" },
                set: { model.pages[i].captions[model.locale, default: .init()].headline = $0 }), axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(1...3)
            TextField(editingPrimary ? "Subheadline" : primary.sub, text: Binding(
                get: { model.pages[i].captions[model.locale]?.sub ?? "" },
                set: { model.pages[i].captions[model.locale, default: .init()].sub = $0 }), axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(1...3)
            if !editingPrimary {
                Text("Empty fields fall back to \(StoreLocales.name(model.primary)).").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Label(model.pages[i].phone == nil ? "No iPhone shot" : "iPhone ✓", systemImage: "iphone").foregroundStyle(model.pages[i].phone == nil ? .orange : .secondary)
                Label(model.pages[i].pad == nil ? "No iPad shot" : "iPad ✓", systemImage: "ipad").foregroundStyle(model.pages[i].pad == nil ? .orange : .secondary)
            }
            .font(.caption)
            HStack {
                Button { model.move(i, by: -1) } label: { Image(systemName: "arrow.left") }.disabled(i == 0)
                Button { model.move(i, by: 1) } label: { Image(systemName: "arrow.right") }.disabled(i == model.pages.count - 1)
                Spacer()
                Button(role: .destructive) { model.pages.remove(at: i) } label: { Image(systemName: "trash") }
            }
        }
    }

    private var languagesPanel: some View {
        Panel(title: "Languages", symbol: "globe") {
            ForEach(model.locales, id: \.self) { code in
                HStack {
                    Image(systemName: model.locale == code ? "checkmark.circle.fill" : "circle").foregroundStyle(model.locale == code ? Color.accentColor : .secondary)
                    Text(StoreLocales.name(code))
                    Text(code).font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                    if model.missing(code) > 0 { Text("\(model.missing(code)) to translate").font(.caption).foregroundStyle(.orange) }
                    if code == model.primary { Text("Primary").font(.caption2).foregroundStyle(.secondary) }
                    else { Button { model.removeLocale(code) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless) }
                }
                .contentShape(Rectangle())
                .onTapGesture { model.locale = code }
            }
            Menu {
                ForEach(StoreLocales.all.filter { !model.locales.contains($0.code) }, id: \.code) { l in
                    Button("\(l.name)  (\(l.code))") { model.addLocale(l.code) }
                }
            } label: { Label("Add Language", systemImage: "plus") }
            HStack {
                Button("Export CSV…") { Inbox.save(Data(model.csv.utf8), name: "App Store captions.csv") }
                Button("Import CSV…") {
                    if let u = Inbox.openPanel(multiple: false, types: [.commaSeparatedText, .plainText]).first,
                       let text = try? String(contentsOf: u, encoding: .utf8) {
                        model.message = "Imported \(model.importCSV(text)) captions."
                    }
                }
            }
            .controlSize(.small)
            Text("CSV columns: page, locale, headline, subheadline. Export, translate in any spreadsheet, import.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var stylePanel: some View {
        Panel(title: "Style", symbol: "rectangle.3.group") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 10) {
                ForEach(StoreStyle.allCases) { s in styleThumb(s) }
            }
            Toggle("Show text", isOn: $model.showText)
            Toggle("Show subheadline", isOn: $model.showSub).disabled(!model.showText)
            Toggle("Device frames", isOn: $model.framed)
            if model.framed {
                Picker("Finish", selection: $model.finish) { ForEach(DeviceFrame.Finish.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
            }
            SliderRow(label: "Shadow", value: $model.shadow, range: 0...1.5) { "\(Int($0 * 100))%" }
            if model.style == .spotlight {
                SliderRow(label: "Spotlight position", value: $model.spotY, range: 0.1...0.9) { "\(Int($0 * 100))%" }
            }
        }
    }

    private func styleThumb(_ s: StoreStyle) -> some View {
        let size = model.device.size, w: CGFloat = 76, k = w / size.width
        let on = model.style == s
        let i = model.selectedIndex ?? 0
        return Button { withAnimation(.snappy) { model.style = s } } label: {
            VStack(spacing: 4) {
                Group {
                    if model.pages.isEmpty { RoundedRectangle(cornerRadius: 4).fill(.quaternary) }
                    else { StorePage(m: model, index: i, device: model.device, locale: model.locale, style: s).scaleEffect(k, anchor: .topLeading) }
                }
                .frame(width: w, height: size.height * k, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(on ? Color.accentColor : .primary.opacity(0.12), lineWidth: on ? 2.5 : 1))
                Text(s.rawValue).font(.system(size: 10)).foregroundStyle(on ? .primary : .secondary).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private var textPanel: some View {
        Panel(title: "Text", symbol: "textformat") {
            FontPicker(family: $model.headline.family, member: $model.headline.member)
            SliderRow(label: "Headline size", value: $model.headline.size, range: 48...180) { "\(Int($0)) px" }
            SliderRow(label: "Letter spacing", value: $model.headline.tracking, range: -10...20)
            ColorPicker("Headline color", selection: $model.headline.color1)
            SliderRow(label: "Subheadline size", value: $model.subSize, range: 28...100) { "\(Int($0)) px" }
            ColorPicker("Subheadline color", selection: $model.subColor)
            Text("Sizes are for iPhone 6.9″ and scale for other devices.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var backgroundPanel: some View {
        Panel(title: "Background", symbol: "square.3.layers.3d") {
            Picker("Background", selection: $model.background) { ForEach(StoreBackground.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden()
            switch model.background {
            case .mesh: MeshPanel(m: model.mesh)
            case .gradient:
                HStack { ColorPicker("From", selection: $model.bg1); ColorPicker("to", selection: $model.bg2) }
            case .color: ColorPicker("Color", selection: $model.bg1)
            case .image:
                Button("Choose Image…") { pick { model.bgImage = $0 } }
            }
            if model.style == .panorama {
                Text("Panorama stretches the background across all pages, so the set reads as one continuous image.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var exportPanel: some View {
        Panel(title: "Export for App Store Connect", symbol: "square.and.arrow.up") {
            ForEach(StoreDevice.allCases) { d in
                Toggle(isOn: Binding(get: { model.exportDevices.contains(d) },
                                     set: { if $0 { model.exportDevices.insert(d) } else { model.exportDevices.remove(d) } })) {
                    HStack {
                        Text(d.rawValue)
                        Text("\(Int(d.size.width))×\(Int(d.size.height))").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        if d == .iphone63 { Text("required").font(.caption2.weight(.semibold)).foregroundStyle(.orange) }
                    }
                }
            }
            Picker("Format", selection: $model.format) {
                Text("PNG").tag(ImageFormat.png)
                Text("JPEG").tag(ImageFormat.jpeg)
            }
            .pickerStyle(.segmented)
            ForEach(model.issues) { issue in
                Label(issue.text, systemImage: issue.error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(issue.error ? .red : .orange)
            }
            let total = model.locales.count * model.exportDevices.count * min(model.pages.count, 10)
            Button {
                guard let folder = Inbox.chooseFolder("Export Here") else { return }
                Task {
                    let out = await model.export(to: folder)
                    NSWorkspace.shared.activateFileViewerSelecting([out])
                }
            } label: {
                Label("Export \(total) Screenshot\(total == 1 ? "" : "s")…", systemImage: "arrow.down.circle.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).tint(Tool.appstore.tint)
            .disabled(model.issues.contains(where: \.error) || model.progress != nil)
            if let p = model.progress { ProgressView(value: p) }
            if let msg = model.message { Label(msg, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green) }
            Text("Folders: language / device / 01.png … — exact pixel sizes, no transparency, ready to drag into App Store Connect.")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }
}
