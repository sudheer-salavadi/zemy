// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Zemy",
    platforms: [.macOS(.v15)],
    products: [.library(name: "ZemyKit", targets: ["ZemyKit"])],
    targets: [
        // libwebp 1.6.0 (BSD) — macOS ImageIO can decode WebP but not encode it.
        .target(
            name: "CWebP",
            path: "Vendor/CWebP",
            exclude: ["COPYING", "PATENTS"],
            sources: ["src/enc", "src/dec", "src/dsp", "src/utils", "sharpyuv"],
            publicHeadersPath: "src/webp",
            cSettings: [.headerSearchPath("."), .unsafeFlags(["-O3", "-w"])]
        ),
        .target(
            name: "ZemyKit",
            dependencies: ["CWebP"],
            path: "Sources/ZemyKit",
            swiftSettings: [.swiftLanguageMode(.v5), .unsafeFlags(["-Ounchecked"])]
        ),
        .executableTarget(name: "Zemy", dependencies: ["ZemyKit"], path: "Sources/Zemy"),
    ]
)
