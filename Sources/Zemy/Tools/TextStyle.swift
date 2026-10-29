import SwiftUI

/// Typography for a Showcase text layer (value type, so each layer has its own).
struct TextStyle: Equatable {
    enum Fill: String, CaseIterable, Identifiable { case solid = "Solid", gradient = "Gradient"; var id: Self { self } }
    enum Align: String, CaseIterable, Identifiable {
        case leading, center, trailing
        var id: Self { self }
        var value: TextAlignment { [.leading: .leading, .center: .center, .trailing: .trailing][self]! }
        var symbol: String { "text.align\(rawValue == "leading" ? "left" : rawValue == "trailing" ? "right" : "center")" }
    }

    var text = "Your headline"
    var family = "Avenir Next"
    var member = "AvenirNext-Heavy"
    var size = 110.0
    var tracking = -1.5
    var lineSpacing = 0.0
    var align = Align.center
    var fill = Fill.solid
    var color1 = Color.white
    var color2 = Color(red: 0.55, green: 0.32, blue: 1)
    var angle = 90.0
    var stroke = 0.0
    var strokeColor = Color.black
    var shadowRadius = 24.0
    var shadowX = 0.0
    var shadowY = 8.0
    var shadowColor = Color.black.opacity(0.3)

    static let presets: [(name: String, apply: (inout TextStyle) -> Void)] = [
        ("Clean", { s in
            s.fill = .solid; s.color1 = .white; s.stroke = 0
            s.shadowColor = .black.opacity(0.3); s.shadowRadius = 24; s.shadowX = 0; s.shadowY = 8
        }),
        ("Ink", { s in
            s.fill = .solid; s.color1 = Color(white: 0.07); s.stroke = 0; s.shadowRadius = 0; s.shadowX = 0; s.shadowY = 0
        }),
        ("Sunset", { s in
            s.fill = .gradient; s.color1 = Color(red: 1, green: 0.42, blue: 0.42); s.color2 = Color(red: 0.55, green: 0.32, blue: 1)
            s.stroke = 0; s.shadowRadius = 0; s.shadowX = 0; s.shadowY = 0
        }),
        ("Neon", { s in
            s.fill = .solid; s.color1 = Color(red: 1, green: 0.35, blue: 0.85); s.stroke = 0
            s.shadowColor = Color(red: 1, green: 0.2, blue: 0.8); s.shadowRadius = 22; s.shadowX = 0; s.shadowY = 0
        }),
        ("Retro", { s in
            s.fill = .solid; s.color1 = Color(red: 1, green: 0.82, blue: 0.25); s.stroke = 6; s.strokeColor = Color(red: 0.2, green: 0.1, blue: 0.3)
            s.shadowColor = Color(red: 0.95, green: 0.35, blue: 0.3); s.shadowRadius = 0; s.shadowX = 10; s.shadowY = 10
        }),
        ("Chrome", { s in
            s.fill = .gradient; s.color1 = Color(white: 0.98); s.color2 = Color(white: 0.45); s.angle = 90
            s.stroke = 2; s.strokeColor = Color(white: 0.3); s.shadowColor = .black.opacity(0.35); s.shadowRadius = 8; s.shadowX = 0; s.shadowY = 6
        }),
    ]
}

/// Renders a TextStyle at its natural size (stroke included, shadow overflows).
struct TextArt: View {
    let style: TextStyle

    var body: some View {
        let s = style
        let base = Text(s.text.isEmpty ? " " : s.text)
            .font(.custom(s.member, size: s.size))
            .tracking(s.tracking)
            .lineSpacing(s.lineSpacing)
            .multilineTextAlignment(s.align.value)
            .fixedSize()
        let rad = s.angle * .pi / 180
        let start = UnitPoint(x: 0.5 - cos(rad) / 2, y: 0.5 - sin(rad) / 2)
        let end = UnitPoint(x: 0.5 + cos(rad) / 2, y: 0.5 + sin(rad) / 2)
        let fill: AnyShapeStyle = s.fill == .solid ? AnyShapeStyle(s.color1)
            : AnyShapeStyle(LinearGradient(colors: [s.color1, s.color2], startPoint: start, endPoint: end))
        let steps = s.stroke > 0 ? min(64, max(16, Int(s.stroke * 4))) : 0

        ZStack {
            ForEach(0..<steps, id: \.self) { i in
                let a = Double(i) / Double(steps) * 2 * .pi
                base.foregroundStyle(s.strokeColor).offset(x: cos(a) * s.stroke, y: sin(a) * s.stroke)
            }
            base.foregroundStyle(fill)
        }
        .compositingGroup()
        .shadow(color: s.shadowRadius > 0 || s.shadowX != 0 || s.shadowY != 0 ? s.shadowColor : .clear,
                radius: s.shadowRadius, x: s.shadowX, y: s.shadowY)
        .padding(s.stroke)
    }

    /// Natural layout size in points (= canvas pixels).
    @MainActor static func measure(_ s: TextStyle) -> CGSize {
        let host = NSHostingView(rootView: TextArt(style: s).fixedSize())
        let size = host.fittingSize
        return CGSize(width: max(size.width, 1), height: max(size.height, 1))
    }
}

/// Inspector panels for editing a text layer.
struct TextStylePanels: View {
    @Binding var style: TextStyle

    var body: some View {
        Panel(title: "Text", symbol: "character.cursor.ibeam") {
            TextEditor(text: $style.text)
                .font(.title3).frame(height: 70)
                .scrollContentBackground(.hidden).padding(6)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 6)], spacing: 6) {
                ForEach(TextStyle.presets, id: \.name) { p in Button(p.name) { p.apply(&style) }.controlSize(.small) }
            }
        }
        Panel(title: "Font", symbol: "textformat.size") {
            FontPicker(family: $style.family, member: $style.member)
            SliderRow(label: "Size", value: $style.size, range: 12...400) { "\(Int($0)) pt" }
            SliderRow(label: "Letter spacing", value: $style.tracking, range: -20...60)
            SliderRow(label: "Line spacing", value: $style.lineSpacing, range: -40...120)
            Picker("Align", selection: $style.align) {
                ForEach(TextStyle.Align.allCases) { Image(systemName: $0.symbol).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        Panel(title: "Fill", symbol: "paintbrush") {
            Picker("Fill", selection: $style.fill) { ForEach(TextStyle.Fill.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden()
            HStack {
                ColorPicker("Color", selection: $style.color1)
                if style.fill == .gradient { ColorPicker("to", selection: $style.color2) }
            }
            if style.fill == .gradient { SliderRow(label: "Angle", value: $style.angle, range: 0...360) { "\(Int($0))°" } }
        }
        Panel(title: "Stroke & Shadow", symbol: "circle.dashed") {
            HStack {
                SliderRow(label: "Stroke", value: $style.stroke, range: 0...20)
                ColorPicker("", selection: $style.strokeColor).labelsHidden()
            }
            HStack {
                SliderRow(label: "Shadow / glow", value: $style.shadowRadius, range: 0...60)
                ColorPicker("", selection: $style.shadowColor).labelsHidden()
            }
            HStack {
                SliderRow(label: "Offset X", value: $style.shadowX, range: -40...40)
                SliderRow(label: "Offset Y", value: $style.shadowY, range: -40...40)
            }
        }
    }
}

/// Installed font families and their styles.
enum Fonts {
    static let families = NSFontManager.shared.availableFontFamilies

    static func members(_ family: String) -> [(ps: String, style: String)] {
        (NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []).compactMap { m in
            guard let ps = m.first as? String, let style = m.dropFirst().first as? String else { return nil }
            return (ps, style)
        }
    }

    static func defaultMember(_ family: String) -> String {
        let ms = members(family)
        return ms.first { $0.style == "Bold" }?.ps ?? ms.first { $0.style == "Regular" }?.ps ?? ms.first?.ps ?? family
    }
}

/// Family button (opens a searchable, self-previewing list) plus a style menu.
struct FontPicker: View {
    @Binding var family: String
    @Binding var member: String
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack {
                Text(family).font(.custom(family, size: 15)).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .popover(isPresented: $open, arrowEdge: .leading) {
            FontBrowser(selected: family) { family = $0; member = Fonts.defaultMember($0); open = false }
        }
        Picker("Style", selection: $member) {
            ForEach(Fonts.members(family), id: \.ps) { Text($0.style).tag($0.ps) }
        }
    }
}

private struct FontBrowser: View {
    let selected: String
    let onPick: (String) -> Void
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search \(Fonts.families.count) fonts", text: $query).textFieldStyle(.roundedBorder).padding(10)
            List(Fonts.families.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }, id: \.self) { f in
                Button { onPick(f) } label: {
                    HStack {
                        Text(f).font(.custom(f, size: 17)).lineLimit(1)
                        Spacer()
                        if f == selected { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 300, height: 440)
    }
}
