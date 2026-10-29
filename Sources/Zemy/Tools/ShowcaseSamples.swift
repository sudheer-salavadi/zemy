import SwiftUI

/// Mock app screens for Showcase's first-run example, drawn in code and rendered once.
enum ShowcaseSamples {
    @MainActor static let images: [CGImage] = [
        render(PhoneMusic(), CGSize(width: 390, height: 844)),
        render(PhoneTasks(), CGSize(width: 390, height: 844)),
        render(Dashboard(), CGSize(width: 1200, height: 780)),
    ].compactMap { $0 }

    @MainActor private static func render(_ view: some View, _ size: CGSize) -> CGImage? {
        let r = ImageRenderer(content: view.frame(width: size.width, height: size.height).environment(\.colorScheme, .light))
        r.scale = 2
        return r.cgImage
    }
}

private let ink = Color(red: 0.09, green: 0.1, blue: 0.16)
private let accent = Color(red: 0.42, green: 0.36, blue: 0.98)

private struct Dashboard: View {
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                RoundedRectangle(cornerRadius: 8).fill(accent).frame(width: 34, height: 34)
                ForEach(["Overview", "Projects", "Reports", "Team", "Settings"], id: \.self) { item in
                    Text(item).font(.system(size: 15, weight: item == "Overview" ? .semibold : .regular))
                        .foregroundStyle(item == "Overview" ? .white : .white.opacity(0.55))
                }
                Spacer()
            }
            .padding(26).frame(width: 200).background(ink)
            VStack(alignment: .leading, spacing: 22) {
                Text("Overview").font(.system(size: 30, weight: .bold)).foregroundStyle(ink)
                HStack(spacing: 16) {
                    stat("Revenue", "$48.2k", "+12.4%")
                    stat("Active users", "2,431", "+8.1%")
                    stat("Uptime", "99.98%", "30 days")
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Weekly growth").font(.system(size: 15, weight: .semibold)).foregroundStyle(ink)
                    HStack(alignment: .bottom, spacing: 12) {
                        ForEach([0.35, 0.5, 0.42, 0.66, 0.58, 0.8, 0.72, 0.92, 0.85, 1.0, 0.9, 0.97], id: \.self) { h in
                            RoundedRectangle(cornerRadius: 5)
                                .fill(LinearGradient(colors: [accent, Color(red: 0.2, green: 0.8, blue: 0.9)], startPoint: .bottom, endPoint: .top))
                                .frame(height: 230 * h)
                        }
                    }
                    .frame(height: 230, alignment: .bottom)
                }
                .padding(20).background(.white, in: RoundedRectangle(cornerRadius: 16))
                Spacer()
            }
            .padding(32).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.96, green: 0.96, blue: 0.98))
        }
    }

    private func stat(_ title: String, _ value: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 28, weight: .bold)).foregroundStyle(ink)
            Text(note).font(.system(size: 12, weight: .medium)).foregroundStyle(.green)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct PhoneMusic: View {
    var body: some View {
        VStack(spacing: 22) {
            Spacer().frame(height: 40)
            RoundedRectangle(cornerRadius: 28)
                .fill(MeshGradient(width: 2, height: 2, points: [[0, 0], [1, 0], [0, 1], [1, 1]],
                                   colors: [.orange, .pink, .purple, Color(red: 0.2, green: 0.3, blue: 0.9)]))
                .frame(width: 310, height: 310)
                .shadow(color: .pink.opacity(0.4), radius: 30, y: 16)
            VStack(spacing: 6) {
                Text("Midnight Drive").font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
                Text("Neon Coast").font(.system(size: 17)).foregroundStyle(.white.opacity(0.6))
            }
            VStack(spacing: 8) {
                Capsule().fill(.white.opacity(0.2)).frame(height: 5)
                    .overlay(alignment: .leading) { Capsule().fill(.white).frame(width: 130, height: 5) }
                HStack { Text("1:24"); Spacer(); Text("3:52") }.font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 40)
            HStack(spacing: 44) {
                Image(systemName: "backward.fill").font(.system(size: 26))
                Image(systemName: "pause.circle.fill").font(.system(size: 64))
                Image(systemName: "forward.fill").font(.system(size: 26))
            }
            .foregroundStyle(.white)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [Color(red: 0.15, green: 0.08, blue: 0.25), Color(red: 0.05, green: 0.04, blue: 0.1)], startPoint: .top, endPoint: .bottom))
    }
}

private struct PhoneTasks: View {
    private let tasks: [(String, String, Color, Bool)] = [
        ("Review landing page", "Design", .purple, true), ("Ship onboarding flow", "Product", .blue, true),
        ("Sync with marketing", "Meeting", .orange, false), ("Polish icon set", "Design", .purple, false),
        ("Write release notes", "Docs", .green, false), ("Plan Q3 roadmap", "Product", .blue, false),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer().frame(height: 36)
            Text("Good morning").font(.system(size: 16)).foregroundStyle(.secondary)
            Text("Today").font(.system(size: 36, weight: .bold)).foregroundStyle(ink)
            HStack(spacing: 10) {
                ForEach(["All 6", "Design 2", "Product 2"], id: \.self) { chip in
                    Text(chip).font(.system(size: 13, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 8)
                        .background(chip.hasPrefix("All") ? accent : Color(white: 0.93), in: Capsule())
                        .foregroundStyle(chip.hasPrefix("All") ? .white : ink)
                }
            }
            ForEach(tasks, id: \.0) { title, tag, color, done in
                HStack(spacing: 14) {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.system(size: 22)).foregroundStyle(done ? accent : Color(white: 0.75))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(ink).strikethrough(done)
                        Text(tag).font(.system(size: 12, weight: .medium)).foregroundStyle(color)
                    }
                    Spacer()
                }
                .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 14))
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .background(Color(red: 0.96, green: 0.96, blue: 0.98))
    }
}
