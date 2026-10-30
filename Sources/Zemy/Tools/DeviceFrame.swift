import SwiftUI

/// Generic iPhone / iPad bezel drawn in code (no Apple artwork), or a bare rounded screenshot when frames are off.
struct DeviceFrame: View {
    enum Finish: String, CaseIterable, Identifiable {
        case black = "Black", silver = "Silver", titanium = "Titanium"
        var id: Self { self }
        var color: Color {
            switch self {
            case .black: Color(white: 0.09)
            case .silver: Color(white: 0.86)
            case .titanium: Color(red: 0.6, green: 0.58, blue: 0.54)
            }
        }
    }

    let image: CGImage?
    let pad: Bool
    let framed: Bool
    let finish: Finish
    let width: CGFloat
    /// Height ÷ width of the screen (the device's screenshot size).
    let screenAspect: CGFloat
    var shadow: Double = 0.6

    static func bezel(_ pad: Bool) -> CGFloat { pad ? 0.022 : 0.028 } // slim, modern bezels

    /// Overall height ÷ width, so layouts can size the device before drawing it.
    static func aspect(pad: Bool, framed: Bool, screenAspect: CGFloat) -> CGFloat {
        guard framed else { return screenAspect }
        let b = bezel(pad)
        return (1 - 2 * b) * screenAspect + 2 * b
    }

    var body: some View {
        let b = framed ? width * Self.bezel(pad) : 0
        let sw = width - 2 * b, sh = sw * screenAspect
        let outer = width * (pad ? 0.055 : 0.14)
        let inner = framed ? max(outer - b, 2) : width * (pad ? 0.04 : 0.1)
        ZStack {
            if framed {
                RoundedRectangle(cornerRadius: outer, style: .continuous).fill(finish.color)
                    .overlay(RoundedRectangle(cornerRadius: outer, style: .continuous)
                        .strokeBorder(.white.opacity(finish == .black ? 0.16 : 0.5), lineWidth: max(1, width * 0.004)))
            }
            screen.frame(width: sw, height: sh)
                .clipShape(RoundedRectangle(cornerRadius: inner, style: .continuous))
            if framed && !pad {
                Capsule().fill(.black)
                    .frame(width: sw * 0.31, height: sw * 0.088)
                    .offset(y: -sh / 2 + sw * 0.075)
            }
        }
        .frame(width: width, height: sh + 2 * b)
        .compositingGroup()
        .shadow(color: .black.opacity(0.35 * shadow), radius: width * 0.05 * shadow, y: width * 0.03 * shadow)
    }

    @ViewBuilder private var screen: some View {
        if let image {
            Image(decorative: image, scale: 1).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
        } else {
            LinearGradient(colors: [Color(white: 0.92), Color(white: 0.8)], startPoint: .top, endPoint: .bottom)
                .overlay(Image(systemName: "photo").font(.system(size: width * 0.12)).foregroundStyle(.secondary))
        }
    }
}
