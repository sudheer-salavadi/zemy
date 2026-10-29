import SwiftUI
import UniformTypeIdentifiers

@MainActor @Observable
final class IconModel {
    var macShape = true
    var fill = false
    var inset = 0.0
    var background = Color.white
    var useBackground = false
    var lastFolder: URL?
}

/// One 1024² master, drawn as a SwiftUI view so preview and export match.
struct IconArt: View {
    let image: CGImage
    let m: IconModel
    /// macOS-style squircle on Apple's 1024 grid (824 body, 100 margin).
    var shaped: Bool

    var body: some View {
        let body: CGFloat = shaped ? 824 : 1024
        let art = Image(decorative: image, scale: 1).resizable()
            .aspectRatio(contentMode: m.fill ? .fill : .fit)
            .padding(body * m.inset)
            .frame(width: body, height: body)
            .background(m.useBackground || (shaped && m.fill == false) ? m.background : .clear)
        Group {
            if shaped {
                art.clipShape(RoundedRectangle(cornerRadius: 185.4, style: .continuous))
                    .shadow(color: .black.opacity(0.28), radius: 10, y: 10)
            } else {
                art.clipped()
            }
        }
        .frame(width: 1024, height: 1024)
    }

    @MainActor static func render(_ image: CGImage, _ m: IconModel, shaped: Bool) -> CGImage? {
        let r = ImageRenderer(content: IconArt(image: image, m: m, shaped: shaped))
        r.scale = 1
        return r.cgImage
    }
}

enum IconExport {
    static func png(_ img: CGImage, _ side: Int, opaque: Bool = false) -> Data? {
        var out = img.resized(to: CGSize(width: side, height: side))
        if opaque { out = out.flattened() }
        return PNG.encode(out)
    }

    static func write(_ data: Data?, _ url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data?.write(to: url)
    }

    static func mac(_ master: CGImage, to folder: URL) {
        let sizes = [16, 32, 64, 128, 256, 512, 1024]
        write(ImageIOKit.write(sizes.map { master.resized(to: CGSize(width: $0, height: $0)) }, type: UTType.icns.identifier),
              folder.appendingPathComponent("AppIcon.icns"))
    }

    static func ios(_ master: CGImage, to folder: URL) {
        let set = folder.appendingPathComponent("AppIcon.appiconset")
        write(png(master, 1024, opaque: true), set.appendingPathComponent("AppIcon-1024.png"))
        let json = """
        {
          "images" : [ { "filename" : "AppIcon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" } ],
          "info" : { "author" : "Zemy", "version" : 1 }
        }
        """
        write(Data(json.utf8), set.appendingPathComponent("Contents.json"))
    }

    static func web(_ master: CGImage, to folder: URL) {
        let dir = folder.appendingPathComponent("favicons")
        write(ImageIOKit.write([16, 32, 48].map { master.resized(to: CGSize(width: $0, height: $0)) }, type: UTType.ico.identifier),
              dir.appendingPathComponent("favicon.ico"))
        write(png(master, 180, opaque: true), dir.appendingPathComponent("apple-touch-icon.png"))
        for s in [32, 192, 512] { write(png(master, s), dir.appendingPathComponent("icon-\(s).png")) }
        let manifest = """
        {
          "icons": [
            { "src": "/icon-192.png", "sizes": "192x192", "type": "image/png" },
            { "src": "/icon-512.png", "sizes": "512x512", "type": "image/png" }
          ]
        }
        """
        write(Data(manifest.utf8), dir.appendingPathComponent("site.webmanifest"))
        let html = """
        <link rel="icon" href="/favicon.ico" sizes="any">
        <link rel="icon" type="image/png" href="/icon-32.png" sizes="32x32">
        <link rel="apple-touch-icon" href="/apple-touch-icon.png">
        <link rel="manifest" href="/site.webmanifest">
        """
        write(Data(html.utf8), dir.appendingPathComponent("snippet.html"))
    }

    static func android(_ master: CGImage, to folder: URL) {
        let dir = folder.appendingPathComponent("android")
        for (name, s) in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)] {
            write(png(master, s), dir.appendingPathComponent("mipmap-\(name)/ic_launcher.png"))
        }
        write(png(master, 512), dir.appendingPathComponent("play-store-512.png"))
    }
}

struct IconToolView: View {
    @Bindable var model: IconModel
    @Environment(AppState.self) private var state

    var body: some View {
        SingleImageTool(tool: .icons) { cur in
            let mac = IconArt.render(cur.image, model, shaped: model.macShape)
            let flat = IconArt.render(cur.image, model, shaped: false)
            VStack(spacing: 28) {
                    if let mac {
                        HStack(alignment: .bottom, spacing: 22) {
                            ForEach([160, 128, 64, 32, 16], id: \.self) { s in
                                VStack {
                                    Image(decorative: mac, scale: 1).resizable().interpolation(.high).frame(width: CGFloat(s), height: CGFloat(s))
                                    Text("\(s)").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if let flat {
                        HStack(spacing: 22) {
                            ForEach([("iOS", 0.2237), ("Android", 0.5)], id: \.0) { label, r in
                                VStack {
                                    Image(decorative: flat, scale: 1).resizable().frame(width: 96, height: 96)
                                        .clipShape(RoundedRectangle(cornerRadius: 96 * r, style: .continuous))
                                        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                                    Text(label).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(24)
                        .background(LinearGradient(colors: [.indigo, .purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                }
            .padding(40)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        } inspector: {
            Panel(title: "Artwork", symbol: "square.on.square") {
                Toggle("macOS squircle & grid", isOn: $model.macShape)
                Toggle("Fill the tile (crop)", isOn: $model.fill)
                SliderRow(label: "Inset", value: $model.inset, range: 0...0.3) { "\(Int($0 * 100))%" }
                Toggle("Background color", isOn: $model.useBackground)
                if model.useBackground || (model.macShape && !model.fill) { ColorPicker("Color", selection: $model.background) }
                Text("iOS & Android get the full-bleed square; the system applies its own mask.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Panel(title: "Generate", symbol: "shippingbox") {
                exportButton("macOS  ·  AppIcon.icns", "laptopcomputer") { IconExport.mac($0, to: $2) }
                exportButton("iOS  ·  AppIcon.appiconset", "iphone") { IconExport.ios($1, to: $2) }
                exportButton("Android  ·  mipmaps", "apps.iphone") { IconExport.android($1, to: $2) }
                Button {
                    generate { mac, flat, folder in
                        IconExport.mac(mac, to: folder); IconExport.ios(flat, to: folder)
                        IconExport.android(flat, to: folder)
                    }
                } label: { Label("Everything…", systemImage: "sparkles").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large).tint(Tool.icons.tint)
            }
        }
    }

    private func exportButton(_ title: String, _ symbol: String, _ action: @escaping (CGImage, CGImage, URL) -> Void) -> some View {
        Button { generate(action) } label: { Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading) }
    }

    private func generate(_ action: @escaping (CGImage, CGImage, URL) -> Void) {
        guard let img = state.current?.image,
              let mac = IconArt.render(img, model, shaped: model.macShape),
              let flat = IconArt.render(img, model, shaped: false),
              let folder = Inbox.chooseFolder("Generate Here") else { return }
        Task.detached {
            action(mac, flat, folder)
            await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
        }
    }
}
