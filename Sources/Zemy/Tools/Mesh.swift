import SwiftUI
import CoreImage

/// Curated palettes; Shuffle stays inside the chosen one.
enum MeshScheme: String, CaseIterable, Identifiable {
    case aurora = "Aurora", sunset = "Sunset", ocean = "Ocean", candy = "Candy", forest = "Forest", ember = "Ember", mono = "Mono", any = "Any"
    var id: Self { self }
    /// Hex colours; `.any` generates analogous hues on the fly.
    var hex: [String] {
        switch self {
        case .aurora: ["0B3D91", "1FA2A6", "34D399", "7C3AED", "22D3EE", "6366F1"]
        case .sunset: ["FF6B6B", "FF9F43", "FECA57", "EE5A9B", "8C52FF", "FF7A59"]
        case .ocean: ["03256C", "1E5EFF", "2EC5FF", "8BE9FD", "0FA3B1", "E0F7FF"]
        case .candy: ["FFB3D9", "C7A6FF", "FFD6A5", "A0E7E5", "FF8FAB", "E4C1F9"]
        case .forest: ["0B3B2E", "1E7B4C", "8BC34A", "C5E1A5", "2E8B57", "F1F8E9"]
        case .ember: ["1A0A0A", "7F1D1D", "DC2626", "F97316", "FBBF24", "450A0A"]
        case .mono: ["0F0F12", "3A3A42", "8A8A94", "D4D4D8", "F4F4F5", "5B5B66"]
        case .any: []
        }
    }
    var palette: [Color] { hex.compactMap { RGB(hex: $0)?.color } }
}

/// 3×3 mesh gradient used as a Showcase background.
@MainActor @Observable
final class MeshModel {
    var points: [SIMD2<Float>] = (0..<9).map { SIMD2(Float($0 % 3) / 2, Float($0 / 3) / 2) }
    var colors: [Color] = []
    var selected: Int? = 4
    var grain = 0.12
    var smooth = true
    var scheme = MeshScheme.aurora

    /// A calm, deterministic default; Shuffle randomises from there.
    init() {
        let p = MeshScheme.aurora.palette
        colors = [p[0], p[5], p[3], p[1], p[2], p[0], p[4], p[1], p[5]]
        points[4] = SIMD2(0.42, 0.56)
        points[1] = SIMD2(0.6, 0)
        points[7] = SIMD2(0.38, 1)
    }

    /// New mesh shape and colour placement, staying within the current scheme.
    func randomize() {
        if scheme == .any {
            let base = Double.random(in: 0...1), spread = Double.random(in: 0.08...0.3)
            colors = (0..<9).map { _ in
                Color(hue: (base + .random(in: -spread...spread) + 1).truncatingRemainder(dividingBy: 1),
                      saturation: .random(in: 0.45...0.95), brightness: .random(in: 0.6...1))
            }
        } else {
            let p = scheme.palette
            colors = (0..<9).map { _ in p.randomElement()!.mix(with: .random() ? .white : .black, by: .random(in: 0...0.12)) }
        }
        for i in points.indices { points[i] = constrain(i, SIMD2(Float(i % 3) / 2, Float(i / 3) / 2) + SIMD2(.random(in: -0.18...0.18), .random(in: -0.18...0.18))) }
    }

    func use(_ s: MeshScheme) {
        scheme = s
        randomize()
    }

    /// Corners stay put, edge points slide along their edge, the centre roams.
    func constrain(_ i: Int, _ p: SIMD2<Float>) -> SIMD2<Float> {
        var p = p.clamped(lowerBound: .zero, upperBound: .one)
        let col = i % 3, row = i / 3
        if col != 1 { p.x = Float(col) / 2 }
        if row != 1 { p.y = Float(row) / 2 }
        return p
    }

    /// Film-grain tile generated once with Core Image.
    static let noise: CGImage? = {
        let ci = CIFilter(name: "CIRandomGenerator")!.outputImage!
            .applyingFilter("CIColorMatrix", parameters: ["inputGVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                                                          "inputBVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                                                          "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                                                          "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1)])
        return ciContext.createCGImage(ci, from: CGRect(x: 0, y: 0, width: 256, height: 256))
    }()
}

struct MeshArt: View {
    let m: MeshModel
    var body: some View {
        MeshGradient(width: 3, height: 3, points: m.points, colors: m.colors, smoothsColors: m.smooth)
            .overlay {
                if m.grain > 0, let n = MeshModel.noise {
                    Image(decorative: n, scale: 1).resizable(resizingMode: .tile).blendMode(.softLight).opacity(m.grain * 2)
                }
            }
    }
}

/// Draggable handles for the movable mesh points, laid over the art in its own coordinates.
struct MeshHandles: View {
    let m: MeshModel
    var body: some View {
        GeometryReader { g in
            ForEach([1, 3, 4, 5, 7], id: \.self) { i in
                let p = m.points[i]
                Circle()
                    .fill(m.colors[i])
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(.white, lineWidth: m.selected == i ? 3 : 2))
                    .shadow(color: .black.opacity(0.4), radius: 3)
                    .position(x: CGFloat(p.x) * g.size.width, y: CGFloat(p.y) * g.size.height)
                    .highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("mesh"))
                        .onChanged { v in
                            m.selected = i
                            m.points[i] = m.constrain(i, SIMD2(Float(v.location.x / g.size.width), Float(v.location.y / g.size.height)))
                        })
            }
        }
        .coordinateSpace(name: "mesh")
    }
}

struct MeshPanel: View {
    @Bindable var m: MeshModel
    @State private var editColors = false

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 8) {
            ForEach(MeshScheme.allCases) { s in
                Button { withAnimation(.smooth(duration: 0.6)) { m.use(s) } } label: {
                    VStack(spacing: 3) {
                        Circle()
                            .fill(s == .any ? AnyShapeStyle(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                                            : AnyShapeStyle(AngularGradient(colors: s.palette + [s.palette[0]], center: .center)))
                            .frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(m.scheme == s ? Color.accentColor : .primary.opacity(0.15), lineWidth: m.scheme == s ? 2.5 : 1))
                        Text(s.rawValue).font(.system(size: 9)).foregroundStyle(m.scheme == s ? .primary : .secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        Button { withAnimation(.smooth(duration: 0.6)) { m.randomize() } } label: {
            Label("Shuffle \(m.scheme.rawValue)", systemImage: "dice").frame(maxWidth: .infinity)
        }
        .controlSize(.large).keyboardShortcut("r", modifiers: .command)
        SliderRow(label: "Grain", value: $m.grain, range: 0...0.5) { "\(Int($0 * 200))%" }
        Toggle("Smooth color blending", isOn: $m.smooth)
        DisclosureGroup("Edit colors", isExpanded: $editColors) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(0..<9, id: \.self) { i in
                    ColorPicker("", selection: $m.colors[i]).labelsHidden()
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(m.selected == i ? Color.accentColor : .clear, lineWidth: 2))
                }
            }
        }
        Text("⌘R shuffles within the scheme.").font(.caption).foregroundStyle(.secondary)
    }
}
