import SwiftUI

@MainActor @Observable
final class FaviconModel {
    enum Source: String, CaseIterable, Identifiable { case image = "Image", glyph = "Letter / Emoji"; var id: Self { self } }

    var source = Source.glyph
    var glyph = "P"
    var glyphColor = Color.white
    var family = "Avenir Next"
    var member = "AvenirNext-Bold"
    var tile = true
    var tileColor = Color(red: 0.36, green: 0.33, blue: 0.95)
    var radius = 0.22
    var padding = 0.14
    var title = "My Website"
    /// Last working image auto-adopted, so revisiting the tool keeps a manual Letter choice.
    var adoptedImage: UUID?

    static let snippet = """
    <link rel="icon" href="/favicon.ico" sizes="any">
    <link rel="icon" type="image/png" href="/icon-32.png" sizes="32x32">
    <link rel="apple-touch-icon" href="/apple-touch-icon.png">
    <link rel="manifest" href="/site.webmanifest">
    """
}

/// 512² master, rendered with ImageRenderer and downsampled for every size.
struct FaviconArt: View {
    let m: FaviconModel
    let image: CGImage?
    var body: some View {
        let side: CGFloat = 512
        ZStack {
            if m.tile {
                RoundedRectangle(cornerRadius: side * m.radius, style: .continuous).fill(m.tileColor)
            }
            Group {
                if m.source == .image, let image {
                    Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Text(m.glyph.isEmpty ? " " : String(m.glyph.prefix(2)))
                        .font(.custom(m.member, size: side * 0.72))
                        .minimumScaleFactor(0.2).lineLimit(1)
                        .foregroundStyle(m.glyphColor)
                }
            }
            .padding(side * m.padding)
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: m.tile ? side * m.radius : 0, style: .continuous))
    }

    @MainActor static func render(_ m: FaviconModel, _ image: CGImage?) -> CGImage? {
        let r = ImageRenderer(content: FaviconArt(m: m, image: image))
        r.scale = 1
        return r.cgImage
    }
}

/// Generic browser chrome (tab strip + address bar) in light or dark.
private struct BrowserTabs: View {
    let icon: CGImage?
    let title: String
    let dark: Bool

    var body: some View {
        let strip = dark ? Color(red: 0.13, green: 0.13, blue: 0.14) : Color(red: 0.87, green: 0.88, blue: 0.90)
        let active = dark ? Color(red: 0.21, green: 0.21, blue: 0.23) : .white
        let ink = dark ? Color(white: 0.91) : Color(white: 0.12)
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 0) {
                HStack(spacing: 6) {
                    ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.85)).frame(width: 10, height: 10) }
                }
                .padding(.horizontal, 12).padding(.bottom, 11)
                tab(title, icon: icon, fill: active, ink: ink, selected: true)
                tab("Docs", icon: icon, fill: .clear, ink: ink.opacity(0.75), selected: false)
                Image(systemName: "plus").font(.system(size: 11, weight: .medium)).foregroundStyle(ink.opacity(0.7))
                    .padding(.horizontal, 10).padding(.bottom, 11)
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            HStack(spacing: 10) {
                ForEach(["chevron.left", "chevron.right", "arrow.clockwise"], id: \.self) {
                    Image(systemName: $0).font(.system(size: 11, weight: .medium)).foregroundStyle(ink.opacity(0.7))
                }
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").font(.system(size: 9))
                    Text("example.com").font(.system(size: 12))
                    Spacer()
                }
                .foregroundStyle(ink.opacity(0.8))
                .padding(.horizontal, 12).frame(height: 26)
                .background(dark ? Color(white: 0.13) : Color(white: 0.94), in: Capsule())
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(active)
        }
        .background(strip)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.black.opacity(dark ? 0.5 : 0.12)))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
    }

    private func tab(_ title: String, icon: CGImage?, fill: Color, ink: Color, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Group {
                if let icon { Image(decorative: icon, scale: 2).interpolation(.high) }
                else { Image(systemName: "globe").font(.system(size: 12)).foregroundStyle(ink.opacity(0.6)) }
            }
            .frame(width: 16, height: 16)
            Text(title).font(.system(size: 12)).foregroundStyle(ink).lineLimit(1).truncationMode(.tail).layoutPriority(-1)
            Spacer(minLength: 4)
            Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(ink.opacity(0.55))
        }
        .padding(.horizontal, 12)
        .frame(minWidth: 64, idealWidth: 190, maxWidth: 190, minHeight: 34, maxHeight: 34)
        .background(fill, in: UnevenRoundedRectangle(topLeadingRadius: 9, topTrailingRadius: 9, style: .continuous))
        .overlay(alignment: .trailing) {
            if !selected { Rectangle().fill(ink.opacity(0.2)).frame(width: 1, height: 16) }
        }
    }
}

struct FaviconToolView: View {
    @Bindable var model: FaviconModel
    @Environment(AppState.self) private var state

    var body: some View {
        let image = state.current?.image
        let master = FaviconArt.render(model, image)
        // Real 32 px pixels, shown at 16 pt — exactly what a Retina tab displays.
        let tabIcon = master?.resized(to: CGSize(width: 32, height: 32))
        ToolScaffold(tool: .favicon) {
            VStack(spacing: 18) {
                BrowserTabs(icon: tabIcon, title: model.title, dark: false)
                BrowserTabs(icon: tabIcon, title: model.title, dark: true)
                if model.source == .image && image == nil {
                    DropZone(tool: .favicon, multiple: false) { state.open($0) }
                } else if let master {
                    HStack(alignment: .bottom, spacing: 26) {
                        ForEach([180, 64, 48, 32, 16], id: \.self) { s in
                            VStack(spacing: 6) {
                                ZStack {
                                    Checkerboard(cell: 6)
                                    Image(decorative: master.resized(to: CGSize(width: s * 2, height: s * 2)), scale: 2)
                                }
                                .frame(width: CGFloat(s), height: CGFloat(s))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                Text("\(s)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(28)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        } inspector: {
            Panel(title: "Source", symbol: "photo") {
                Picker("Source", selection: $model.source) { ForEach(FaviconModel.Source.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden()
                if model.source == .glyph {
                    HStack {
                        TextField("Letter or emoji", text: $model.glyph).textFieldStyle(.roundedBorder).font(.title3)
                        ColorPicker("", selection: $model.glyphColor).labelsHidden()
                    }
                    FontPicker(family: $model.family, member: $model.member)
                } else {
                    Text(image == nil ? "Drop, paste or choose an image." : "Using the working image “\(state.current?.name ?? "")”.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Panel(title: "Tile", symbol: "app") {
                Toggle("Background tile", isOn: $model.tile)
                if model.tile {
                    ColorPicker("Color", selection: $model.tileColor)
                    SliderRow(label: "Corner radius", value: $model.radius, range: 0...0.5) { $0 >= 0.5 ? "Circle" : "\(Int($0 * 200))%" }
                }
                SliderRow(label: "Padding", value: $model.padding, range: 0...0.35) { "\(Int($0 * 100))%" }
            }
            Panel(title: "Preview", symbol: "macwindow") {
                TextField("Tab title", text: $model.title).textFieldStyle(.roundedBorder)
            }
            Panel(title: "Favicon Pack", symbol: "shippingbox") {
                Button {
                    guard let master, let folder = Inbox.chooseFolder("Generate Here") else { return }
                    Task.detached {
                        IconExport.web(master, to: folder)
                        await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting([folder.appendingPathComponent("favicons")]) }
                    }
                } label: { Label("Generate Favicon Pack…", systemImage: "sparkles").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large).tint(Tool.favicon.tint)
                Text("favicon.ico (16·32·48), icon-32/192/512.png, apple-touch-icon.png, site.webmanifest and an HTML snippet.")
                    .font(.caption).foregroundStyle(.secondary)
                CopyButton(text: { FaviconModel.snippet }, label: "Copy HTML snippet").buttonStyle(.borderless)
            }
            ExportPanel(id: "favicon", name: "favicon", formats: [.png, .ico, .webp, .icns]) { _ in master }
        }
        .onChange(of: state.current?.id, initial: true) { _, id in
            if let id, id != model.adoptedImage { model.adoptedImage = id; model.source = .image }
        }
    }
}
