#if DEBUG
import AppKit
import UniformTypeIdentifiers

/// Debug builds only: `ZEMY_SNAPSHOTS=<dir> [ZEMY_IMAGE=<file>]` walks every tool and
/// saves a PNG of the window for each, then quits. Lets UI be reviewed without screen-recording rights.
extension AppState {
    func runSnapshotsIfRequested() {
        if let path = ProcessInfo.processInfo.environment["ZEMY_DROPTEST"] {
            let url = URL(fileURLWithPath: path)
            let finderLike = NSItemProvider(contentsOf: url)!
            let dataOnly = NSItemProvider()
            let data = try! Data(contentsOf: url)
            dataOnly.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { $0(data, nil); return nil }
            dataOnly.suggestedName = "Browser Hero Image"
            if ProcessInfo.processInfo.environment["ZEMY_DRAGPB"] != nil {
                let pb = NSPasteboard(name: .drag); pb.clearContents(); pb.writeObjects([url as NSURL])
            }
            Inbox.load([finderLike, dataOnly]) { urls in
                for u in urls { print("drop →", u.lastPathComponent, Inbox.isTempCopy(u) ? "(temp copy)" : "(original file: \(u.path))") }
                NSApp.terminate(nil)
            }
            return
        }
        if ProcessInfo.processInfo.environment["ZEMY_SVGTEST"] != nil {
            Task {
                let hostile = ##"<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><rect width="100" height="100" fill="#00ff00"/><image href="https://example.com/x.png" width="100" height="100"/><script>document.querySelector('rect').setAttribute('fill','#ff0000')</script></svg>"##
                for (name, src) in [("sample", svg.source), ("hostile", hostile)] {
                    let size = name == "sample" ? svg.size : CGSize(width: 100, height: 100)
                    guard let img = await SVGRenderer.render(src, size: size, scale: 1) else { print(name, "render failed"); continue }
                    let px = img.rgba()
                    let c = px[img.width / 2, img.height / 2]
                    print(name, "rendered \(img.width)x\(img.height), center rgba:", c.x, c.y, c.z, c.w)
                }
                NSApp.terminate(nil)
            }
            return
        }
        guard let dir = ProcessInfo.processInfo.environment["ZEMY_SNAPSHOTS"] else { return }
        print("saved layouts loaded:", showcase.saved.map(\.name))
        if let r = ProcessInfo.processInfo.environment["ZEMY_RENAME"]?.components(separatedBy: "|"), r.count == 6 {
            rename.prefix = r[0]; rename.suffix = r[1]; rename.trimStart = Double(r[2]) ?? 0; rename.trimEnd = Double(r[3]) ?? 0
            rename.find = r[4]; rename.caseStyle = RenameModel.CaseStyle(rawValue: r[5]) ?? .keep
        }
        if let start = ProcessInfo.processInfo.environment["ZEMY_START"].flatMap(Tool.init(rawValue:)) { tool = start }
        if let img = ProcessInfo.processInfo.environment["ZEMY_IMAGE"] {
            let urls = img.split(separator: ",").map { URL(fileURLWithPath: String($0)) }
            let url = urls[0]
            open(urls)
            if tool.isBatch { batches.filter { $0.key != tool }.values.forEach { $0.add([url]) } }
        }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if ProcessInfo.processInfo.environment["ZEMY_TEXT"] != nil { showcase.addText() }
            if ProcessInfo.processInfo.environment["ZEMY_DORENAME"] != nil { rename.apply(); print("rename result:", rename.message ?? "nil") }
            if let st = ProcessInfo.processInfo.environment["ZEMY_STYLE"].flatMap(StoreStyle.init(rawValue:)) { store.style = st }
            if let dev = ProcessInfo.processInfo.environment["ZEMY_DEVICE"].flatMap(StoreDevice.init(rawValue:)) { store.device = dev }
            if ProcessInfo.processInfo.environment["ZEMY_GERMAN"] != nil {
                store.addLocale("de-DE")
                store.pages[0].captions["de-DE"] = .init(headline: "Musik, die dich bewegt", sub: "Wunderschöne Wiedergabe auf jedem Gerät")
            }
            if let out = ProcessInfo.processInfo.environment["ZEMY_STOREEXPORT"] {
                let dir = await store.export(to: URL(fileURLWithPath: out))
                print("store export:", store.message ?? "", "→", dir.path)
            }
            if let out = ProcessInfo.processInfo.environment["ZEMY_SHOWCASEEXPORT"] {
                for (n, l) in ShowcaseModel.Layout.allCases.enumerated() {
                    showcase.arrange(l)
                    if let img = ShowcaseArt.render(showcase)?.flattened(), let png = PNG.encode(img, colors: 0) {
                        try? png.write(to: URL(fileURLWithPath: "\(out)/\(String(format: "%02d", n + 1)) Showcase – \(l.rawValue).png"))
                    }
                }
                showcase.arrange(.hero)
            }
            if let l = ProcessInfo.processInfo.environment["ZEMY_LAYOUT"].flatMap(ShowcaseModel.Layout.init(rawValue:)) { showcase.arrange(l) }
            if ProcessInfo.processInfo.environment["ZEMY_SAVE"] != nil { showcase.arrange(.fan); showcase.saveCurrent(as: "Test fan") }
            if ProcessInfo.processInfo.environment["ZEMY_SCROLL"] != nil { showcase.selected = nil }
            try? await Task.sleep(for: .seconds(0.5 + (Double(ProcessInfo.processInfo.environment["ZEMY_WAIT"] ?? "0") ?? 0)))
            for t in (ProcessInfo.processInfo.environment["ZEMY_TOOLS"]?.split(separator: ",").compactMap { Tool(rawValue: String($0)) } ?? Tool.allCases) {
                tool = t
                try? await Task.sleep(for: .seconds([.background, .svg].contains(t) ? 4 : 1.5))
                guard let view = NSApp.windows.first(where: { $0.isVisible })?.contentView?.superview,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(t.rawValue).png"))
            }
            NSApp.terminate(nil)
        }
    }
}
#endif
