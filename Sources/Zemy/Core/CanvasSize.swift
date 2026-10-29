import SwiftUI

struct CanvasPreset: Identifiable {
    let platform: String, name: String, width: Double, height: Double
    var id: String { platform + name }
    var title: String { "\(platform) · \(name)" }
    var fileName: String { "\(platform) \(name) \(Int(width))x\(Int(height))" }
    var symbol: String { width > height ? "rectangle" : width < height ? "rectangle.portrait" : "square" }
}

/// Recommended upload sizes per platform, shared by every fixed-canvas tool.
enum CanvasPresets {
    static let platforms: [(String, [CanvasPreset])] = [
        ("Instagram", [("Square post", 1080, 1080), ("Portrait post", 1080, 1350), ("Story / Reel", 1080, 1920)]),
        ("TikTok", [("Video cover", 1080, 1920)]),
        ("X / Twitter", [("Post image", 1600, 900), ("Header", 1500, 500)]),
        ("Facebook", [("Feed post", 1200, 630), ("Square post", 1080, 1080), ("Cover", 1640, 624), ("Story", 1080, 1920)]),
        ("LinkedIn", [("Post", 1200, 627), ("Square post", 1200, 1200), ("Profile banner", 1584, 396)]),
        ("YouTube", [("Thumbnail", 1280, 720), ("Channel banner", 2560, 1440)]),
        ("Pinterest", [("Standard pin", 1000, 1500)]),
        ("Threads", [("Post", 1080, 1350)]),
        ("Dribbble", [("Shot", 1600, 1200)]),
        ("Web", [("Open Graph / link preview", 1200, 630), ("Blog hero", 1920, 1080)]),
        ("Wallpaper", [("Full HD", 1920, 1080), ("4K", 3840, 2160), ("MacBook", 3024, 1964), ("iPhone", 1290, 2796)]),
        ("Slides", [("16:9", 1920, 1080), ("4:3", 1600, 1200)]),
    ].map { platform, sizes in (platform, sizes.map { CanvasPreset(platform: platform, name: $0.0, width: $0.1, height: $0.2) }) }

    static func match(_ w: Double, _ h: Double) -> CanvasPreset? {
        platforms.flatMap(\.1).first { $0.width == w && $0.height == h }
    }
}

/// Platform menu + orientation swap + exact W/H fields.
struct CanvasSizePicker: View {
    @Binding var width: Double
    @Binding var height: Double

    var body: some View {
        let current = CanvasPresets.match(width, height)
        HStack {
            Menu {
                ForEach(CanvasPresets.platforms, id: \.0) { platform, sizes in
                    Section(platform) {
                        ForEach(sizes) { p in
                            Button { width = p.width; height = p.height } label: {
                                Label("\(p.name)  —  \(Int(p.width)) × \(Int(p.height))", systemImage: p.symbol)
                            }
                        }
                    }
                }
            } label: {
                Label(current?.title ?? "Custom size", systemImage: current?.symbol ?? "rectangle.dashed")
            }
            Button { (width, height) = (height, width) } label: { Image(systemName: "rotate.right") }
                .help("Swap portrait / landscape")
        }
        HStack { NumberField(label: "W", value: $width); NumberField(label: "H", value: $height) }
    }
}
