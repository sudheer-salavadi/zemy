import SwiftUI
import ImageIO
import UniformTypeIdentifiers

@MainActor @Observable
final class RenameModel {
    enum CaseStyle: String, CaseIterable, Identifiable {
        case keep = "Keep", lower = "lowercase", upper = "UPPERCASE", title = "Title Case", kebab = "kebab-case", snake = "snake_case", camel = "camelCase"
        var id: Self { self }
    }
    enum Sort: String, CaseIterable, Identifiable { case added = "As added", name = "Name", date = "Date modified"; var id: Self { self } }

    struct Item: Identifiable {
        let id = UUID()
        var url: URL
        let size: CGSize?
        let modified: Date
    }

    struct Row: Identifiable {
        let item: Item
        let newName: String
        let problem: String?
        var id: UUID { item.id }
        var changed: Bool { newName != item.url.lastPathComponent }
    }

    enum Base: String, CaseIterable, Identifiable { case original = "Original name", pattern = "New name"; var id: Self { self } }

    var items: [Item] = []
    /// Start from the existing name (edit it) or build a brand-new one from the pattern.
    var base = Base.original
    var pattern = "{folder}-{n}"
    var prefix = ""
    var suffix = ""
    var trimStart = 0.0
    var trimEnd = 0.0
    var find = ""
    var replace = ""
    var regex = false
    var caseStyle = CaseStyle.keep
    var lowercaseExt = false
    var start = 1.0
    var padding = 2.0
    var step = 1.0
    var sort = Sort.added
    var lastBatch: [(from: URL, to: URL)] = []
    var message: String?

    static let tokens = ["{name}", "{n}", "{folder}", "{date}", "{w}", "{h}"]

    struct Preset { let name: String; let apply: (RenameModel) -> Void }
    static let presets: [Preset] = [
        Preset(name: "Web-ready") { $0.base = .original; $0.caseStyle = .kebab; $0.lowercaseExt = true },
        Preset(name: "Numbered") { $0.base = .pattern; $0.pattern = "{folder}-{n}"; $0.caseStyle = .kebab; $0.lowercaseExt = true },
        Preset(name: "With size") { $0.base = .original; $0.suffix = "@{w}x{h}" },
        Preset(name: "Dated") { $0.base = .original; $0.prefix = "{date}-" },
        Preset(name: "Reset") { m in
            m.base = .original; m.prefix = ""; m.suffix = ""; m.trimStart = 0; m.trimEnd = 0
            m.find = ""; m.replace = ""; m.caseStyle = .keep; m.lowercaseExt = false
        },
    ]

    /// Reads file info off the main thread (a macOS privacy prompt must never freeze the window).
    func add(_ urls: [URL]) {
        Task {
            let new = await Task.detached { Self.items(for: Inbox.expand(urls, imagesOnly: false)) }.value
            let known = Set(items.map(\.url))
            items += new.filter { !known.contains($0.url) }
            message = nil
        }
    }

    nonisolated static func items(for urls: [URL]) -> [Item] {
        urls.filter { !$0.hasDirectoryPath }.map { url in
            let props = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
            let size = (props?[kCGImagePropertyPixelWidth] as? Int).flatMap { w in (props?[kCGImagePropertyPixelHeight] as? Int).map { CGSize(width: w, height: $0) } }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now
            return Item(url: url, size: size, modified: modified)
        }
    }

    // MARK: Naming

    private var ordered: [Item] {
        switch sort {
        case .added: items
        case .name: items.sorted { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
        case .date: items.sorted { $0.modified < $1.modified }
        }
    }

    private static let day: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }()

    func name(for item: Item, index: Int) -> String {
        // 1. Edit the existing name: trim, then find & replace (empty replace = remove).
        var name = item.url.deletingPathExtension().lastPathComponent
        name = String(name.dropFirst(Int(trimStart)).dropLast(Int(trimEnd)))
        if !find.isEmpty {
            name = regex ? name.replacingOccurrences(of: find, with: replace, options: .regularExpression)
                         : name.replacingOccurrences(of: find, with: replace)
        }
        // 2. Expand tokens. The case style shapes the name; prefix and suffix stay exactly as typed.
        let n = Int(start) + index * Int(step)
        func expand(_ t: String) -> String {
            var t = t
            if item.size == nil { // non-images: drop size tokens with their separators
                for sep in ["@", "-", "_", " ", ""] { t = t.replacingOccurrences(of: "\(sep){w}x{h}", with: "") }
            }
            return t
                .replacingOccurrences(of: "{name}", with: name)
                .replacingOccurrences(of: "{n}", with: String(format: "%0\(Int(padding))d", n))
                .replacingOccurrences(of: "{folder}", with: item.url.deletingLastPathComponent().lastPathComponent)
                .replacingOccurrences(of: "{date}", with: Self.day.string(from: item.modified))
                .replacingOccurrences(of: "{w}", with: item.size.map { String(Int($0.width)) } ?? "")
                .replacingOccurrences(of: "{h}", with: item.size.map { String(Int($0.height)) } ?? "")
        }
        let core = Self.restyle(expand(base == .original ? "{name}" : pattern), caseStyle)
        let s = (expand(prefix) + core + expand(suffix)).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let ext = item.url.pathExtension
        return ext.isEmpty ? s : "\(s).\(lowercaseExt ? ext.lowercased() : ext)"
    }

    static func restyle(_ s: String, _ style: CaseStyle) -> String {
        let words = s.replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            .split { !$0.isLetter && !$0.isNumber }.map(String.init)
        switch style {
        case .keep: return s
        case .lower: return s.lowercased()
        case .upper: return s.uppercased()
        case .title: return words.map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " ")
        case .kebab: return words.map { $0.lowercased() }.joined(separator: "-")
        case .snake: return words.map { $0.lowercased() }.joined(separator: "_")
        case .camel: return words.enumerated().map { $0.offset == 0 ? $0.element.lowercased() : $0.element.prefix(1).uppercased() + $0.element.dropFirst().lowercased() }.joined()
        }
    }

    /// Preview rows with conflicts flagged (case-insensitive, like APFS).
    var rows: [Row] {
        let list = ordered
        let names = list.enumerated().map { name(for: $0.element, index: $0.offset) }
        let targets = zip(list, names).map { $0.url.deletingLastPathComponent().appendingPathComponent($1).path.lowercased() }
        var counts: [String: Int] = [:]
        targets.forEach { counts[$0, default: 0] += 1 }
        let sources = Set(list.map { $0.url.path.lowercased() })
        return zip(list, names).enumerated().map { i, pair in
            let (item, new) = pair
            let t = targets[i]
            let problem: String? =
                Inbox.isTempCopy(item.url) ? "Copy of a dropped image — the original can't be renamed"
                : new.hasPrefix(".") || new.isEmpty ? "Empty name"
                : counts[t, default: 0] > 1 ? "Duplicate name"
                : t != item.url.path.lowercased() && !sources.contains(t) && FileManager.default.fileExists(atPath: t) ? "File already exists"
                : nil
            return Row(item: item, newName: new, problem: problem)
        }
    }

    // MARK: Renaming

    /// Two-phase move (via temp names) so swaps like a→b, b→a are safe.
    /// All-or-nothing: if any step fails, everything already moved goes back to its original name.
    private func move(_ plan: [(from: URL, to: URL)]) throws {
        let fm = FileManager.default
        var staged: [(orig: URL, tmp: URL, to: URL)] = []
        var done: [(orig: URL, to: URL)] = []
        do {
            for step in plan {
                let tmp = step.from.deletingLastPathComponent().appendingPathComponent(".zemy-\(UUID().uuidString)")
                try fm.moveItem(at: step.from, to: tmp)
                staged.append((step.from, tmp, step.to))
            }
            for s in staged {
                try fm.moveItem(at: s.tmp, to: s.to)
                done.append((s.orig, s.to))
            }
        } catch {
            for d in done.reversed() { try? fm.moveItem(at: d.to, to: d.orig) }
            for s in staged where !done.contains(where: { $0.orig == s.orig }) { try? fm.moveItem(at: s.tmp, to: s.orig) }
            throw error
        }
    }

    /// Folder macOS refused to let us write to (Desktop, Documents, Downloads… need the user's OK).
    var blockedFolder: URL?

    private static func isPermission(_ error: Error) -> Bool {
        let e = error as NSError
        let underlying = e.userInfo[NSUnderlyingErrorKey] as? NSError
        return [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(e.code)
            || (underlying?.domain == NSPOSIXErrorDomain && [1, 13].contains(underlying?.code))
            || (e.domain == NSPOSIXErrorDomain && [1, 13].contains(e.code))
    }

    func apply() {
        let plan = rows.filter(\.changed).map { (from: $0.item.url, to: $0.item.url.deletingLastPathComponent().appendingPathComponent($0.newName)) }
        guard !plan.isEmpty else { return }
        do {
            try move(plan)
            remap(plan)
            lastBatch = plan.map { (from: $0.to, to: $0.from) }
            blockedFolder = nil
            message = "Renamed \(plan.count) file\(plan.count == 1 ? "" : "s")."
        } catch {
            if Self.isPermission(error) {
                blockedFolder = plan[0].from.deletingLastPathComponent()
                message = nil
            } else {
                message = "Nothing was renamed: \(error.localizedDescription)"
            }
        }
    }

    /// Choosing the folder in an Open panel counts as the user's permission; then retry.
    func grantAccess() {
        guard let folder = blockedFolder else { return }
        let panel = NSOpenPanel()
        panel.directoryURL = folder
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Grant Access"
        panel.message = "Select “\(folder.lastPathComponent)” so Zemy can rename the files in it."
        guard panel.runModal() == .OK else { return }
        apply()
    }

    func undo() {
        guard !lastBatch.isEmpty else { return }
        do {
            try move(lastBatch)
            remap(lastBatch)
            message = "Restored \(lastBatch.count) original name\(lastBatch.count == 1 ? "" : "s")."
            lastBatch = []
        } catch {
            message = "Undo failed: \(error.localizedDescription)"
        }
    }

    private func remap(_ plan: [(from: URL, to: URL)]) {
        let map = Dictionary(uniqueKeysWithValues: plan.map { ($0.from, $0.to) })
        for i in items.indices { if let to = map[items[i].url] { items[i].url = to } }
    }
}

struct RenameToolView: View {
    @Bindable var model: RenameModel
    @Environment(AppState.self) private var state

    var body: some View {
        let rows = model.rows
        let problems = rows.filter { $0.problem != nil }.count
        let changes = rows.filter(\.changed).count
        ToolScaffold(tool: .rename) {
            if model.items.isEmpty {
                DropZone(tool: .rename, types: [.item, .folder]) { state.open($0) }
            } else {
                List {
                    ForEach(rows) { row in
                        HStack(spacing: 10) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: row.item.url.path)).resizable().frame(width: 22, height: 22)
                            Text(row.item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                            Text(row.newName).lineLimit(1).truncationMode(.middle)
                                .fontWeight(row.changed ? .semibold : .regular)
                                .foregroundStyle(row.problem != nil ? AnyShapeStyle(.red) : row.changed ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if Inbox.isTempCopy(row.item.url) {
                                Image(systemName: "doc.on.doc").foregroundStyle(.orange).help("Temporary copy — the original file isn't renamed")
                            }
                            if let p = row.problem {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).help(p)
                            }
                        }
                        .font(.system(.callout, design: .monospaced))
                        .contextMenu {
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([row.item.url]) }
                            Button("Remove from List", role: .destructive) { model.items.removeAll { $0.id == row.id } }
                        }
                    }
                }
                .imageDrop { state.open($0) }
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let folder = model.blockedFolder { permissionBanner(folder) }
                }
            }
        } inspector: {
            Panel(title: "Name", symbol: "textformat.abc") {
                Picker("Start from", selection: $model.base) { ForEach(RenameModel.Base.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden()
                if model.base == .pattern {
                    TextField("Pattern", text: $model.pattern).textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                    FlowTokens(tokens: RenameModel.tokens) { model.pattern += $0 }
                    Text("Replaces the old name entirely. Use {name} to bring it back.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Edits each file's current name.").font(.caption).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 6)], spacing: 6) {
                    ForEach(RenameModel.presets, id: \.name) { p in Button(p.name) { p.apply(model) }.controlSize(.small) }
                }
            }
            Panel(title: "Add", symbol: "plus.rectangle") {
                LabeledContent("Prefix") { TextField("e.g. hero-", text: $model.prefix).textFieldStyle(.roundedBorder) }
                LabeledContent("Suffix") { TextField("e.g. -{n} or @2x", text: $model.suffix).textFieldStyle(.roundedBorder) }
                Text("Tokens: {n} counter · {folder} · {date} · {w} {h} pixels").font(.caption).foregroundStyle(.secondary)
            }
            Panel(title: "Remove", symbol: "scissors") {
                Stepper("First \(Int(model.trimStart)) characters", value: $model.trimStart, in: 0...200)
                Stepper("Last \(Int(model.trimEnd)) characters", value: $model.trimEnd, in: 0...200)
                TextField("Find", text: $model.find).textFieldStyle(.roundedBorder)
                TextField("Replace with (empty removes it)", text: $model.replace).textFieldStyle(.roundedBorder)
                Toggle("Regular expression", isOn: $model.regex)
                Text("Applied to the original name, before prefix and suffix.").font(.caption).foregroundStyle(.secondary)
            }
            Panel(title: "Case", symbol: "textformat") {
                Picker("Style", selection: $model.caseStyle) { ForEach(RenameModel.CaseStyle.allCases) { Text($0.rawValue).tag($0) } }
                Toggle("Lowercase extension", isOn: $model.lowercaseExt)
            }
            Panel(title: "Numbering", symbol: "number") {
                HStack {
                    NumberField(label: "Start", value: $model.start, unit: "")
                    NumberField(label: "Step", value: $model.step, unit: "")
                }
                Stepper("Digits: \(Int(model.padding))", value: $model.padding, in: 1...6)
                Picker("Order", selection: $model.sort) { ForEach(RenameModel.Sort.allCases) { Text($0.rawValue).tag($0) } }
            }
            Panel(title: "Rename", symbol: "checkmark.circle") {
                if !model.items.isEmpty {
                    Text(problems > 0 ? "\(problems) conflict\(problems == 1 ? "" : "s") to fix first" : "\(changes) of \(rows.count) files will change")
                        .font(.callout).foregroundStyle(problems > 0 ? .red : .secondary)
                }
                if let msg = model.message {
                    Label(msg, systemImage: msg.hasPrefix("Nothing") ? "xmark.octagon.fill" : "checkmark.circle.fill")
                        .font(.callout).foregroundStyle(msg.hasPrefix("Nothing") ? .red : .green)
                }
                if model.blockedFolder != nil {
                    Label("Blocked by macOS privacy — see the banner above the list.", systemImage: "lock.shield").font(.callout).foregroundStyle(.orange)
                }
                Button { model.apply() } label: {
                    Label("Rename \(changes) File\(changes == 1 ? "" : "s")", systemImage: "pencil.line").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Tool.rename.tint)
                .disabled(changes == 0 || problems > 0)
                Button { model.undo() } label: { Label("Undo Last Rename", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity) }
                    .disabled(model.lastBatch.isEmpty)
                if model.items.contains(where: { Inbox.isTempCopy($0.url) }) {
                Label("Some items arrived as copies (from a browser, Photos or a screenshot thumbnail), so their originals can't be renamed. Remove them, or drag the files from Finder.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                Button("Remove Copies") { model.items.removeAll { Inbox.isTempCopy($0.url) } }.controlSize(.small)
            }
                Text("Files are renamed in place. Undo restores the last batch.").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .toolbar {
            if !model.items.isEmpty {
                Button { state.open(Inbox.openPanel(types: [.item, .folder])) } label: { Label("Add Files", systemImage: "plus") }
                Button { model.items.removeAll(); model.lastBatch = []; model.message = nil } label: { Label("Clear", systemImage: "trash") }
            }
        }
    }
}

extension RenameToolView {
    func permissionBanner(_ folder: URL) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("macOS didn't let Zemy rename files in “\(folder.lastPathComponent)”").font(.headline)
                Text("Desktop, Documents and Downloads are protected. Nothing was changed. Grant access once and the rename runs again.")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(3)
                HStack {
                    Button("Grant Access…") { model.grantAccess() }.buttonStyle(.borderedProminent)
                    Button("Open Privacy Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!)
                    }
                    Button("Dismiss") { model.blockedFolder = nil }.buttonStyle(.borderless)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// Wrapping row of tappable token chips.
private struct FlowTokens: View {
    let tokens: [String]
    let insert: (String) -> Void
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 6)], spacing: 6) {
            ForEach(tokens, id: \.self) { t in
                Button(t) { insert(t) }.font(.system(.caption, design: .monospaced)).controlSize(.small)
            }
        }
    }
}
