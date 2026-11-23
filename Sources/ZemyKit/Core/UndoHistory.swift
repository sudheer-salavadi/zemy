import SwiftUI

@MainActor protocol UndoTracking: AnyObject {
    var canUndo: Bool { get }
    var canRedo: Bool { get }
    func undo()
    func redo()
}

/// Snapshot undo for a model: watches `get` and records the state before each burst of edits,
/// so a slider drag or a run of keystrokes is one step.
@MainActor @Observable
final class UndoHistory<State: Equatable>: UndoTracking {
    static var limit: Int { 50 }

    private(set) var undoStack: [State] = []
    private(set) var redoStack: [State] = []
    var canUndo: Bool { pending != nil || !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    @ObservationIgnored private let get: () -> State
    @ObservationIgnored private let set: (State) -> Void
    @ObservationIgnored private var settled: State
    @ObservationIgnored private var absorbing = false
    private var pending: Task<Void, Never>?

    init(get: @escaping () -> State, set: @escaping (State) -> Void) {
        self.get = get
        self.set = set
        settled = get()
        track()
    }

    private func track() {
        withObservationTracking { _ = get() } onChange: { [weak self] in
            Task { @MainActor in self?.changed() }
        }
    }

    private func changed() {
        track()
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.commit()
        }
    }

    private func commit() {
        pending?.cancel()
        pending = nil
        let now = get()
        // Follow-on changes a restore triggers (re-layout, reprocessing) belong to that restore.
        if absorbing { absorbing = false; settled = now; return }
        if now != settled {
            undoStack.append(settled)
            if undoStack.count > Self.limit { undoStack.removeFirst(undoStack.count - Self.limit) }
            redoStack.removeAll()
        }
        settled = now
    }

    func undo() {
        if pending != nil { commit() }
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(settled)
        restore(prev)
    }

    func redo() {
        if pending != nil { commit() }
        guard let next = redoStack.popLast() else { return }
        undoStack.append(settled)
        restore(next)
    }

    private func restore(_ s: State) {
        set(s)
        settled = s
        absorbing = true
        changed()
    }
}

// MARK: - Model snapshots

extension MeshModel {
    struct State: Equatable {
        var points: [SIMD2<Float>], colors: [Color], grain: Double, smooth: Bool, scheme: MeshScheme
    }
    var state: State {
        get { State(points: points, colors: colors, grain: grain, smooth: smooth, scheme: scheme) }
        set { points = newValue.points; colors = newValue.colors; grain = newValue.grain; smooth = newValue.smooth; scheme = newValue.scheme }
    }
}

extension ShowcaseModel {
    struct State: Equatable {
        var layers: [Layer], arrangement: Arrangement, seed: UInt64, width: Double, height: Double
        var frame: Frame, darkChrome: Bool, shadow: Double
        var background: Background, bgColor: Color, bgImage: CGImage?, bgBlur: Double, trim: Bool
        var mesh: MeshModel.State
    }
    var state: State {
        get {
            State(layers: layers, arrangement: arrangement, seed: seed, width: width, height: height,
                  frame: frame, darkChrome: darkChrome, shadow: shadow,
                  background: background, bgColor: bgColor, bgImage: bgImage, bgBlur: bgBlur, trim: trim, mesh: mesh.state)
        }
        set {
            layers = newValue.layers; arrangement = newValue.arrangement; seed = newValue.seed
            width = newValue.width; height = newValue.height
            frame = newValue.frame; darkChrome = newValue.darkChrome; shadow = newValue.shadow
            background = newValue.background; bgColor = newValue.bgColor; bgImage = newValue.bgImage
            bgBlur = newValue.bgBlur; trim = newValue.trim; mesh.state = newValue.mesh
            if let s = selected, !layers.contains(where: { $0.id == s }) { selected = nil }
        }
    }
}

extension StoreModel {
    struct State: Equatable {
        var pages: [Page], exportDevices: Set<StoreDevice>, style: StoreStyle
        var showText: Bool, showSub: Bool, framed: Bool, finish: DeviceFrame.Finish, shadow: Double
        var headline: TextStyle, subSize: Double, subColor: Color
        var background: StoreBackground, bg1: Color, bg2: Color, bgImage: CGImage?, mesh: MeshModel.State, spotY: Double
        var locales: [String], format: ImageFormat
    }
    var state: State {
        get {
            State(pages: pages, exportDevices: exportDevices, style: style,
                  showText: showText, showSub: showSub, framed: framed, finish: finish, shadow: shadow,
                  headline: headline, subSize: subSize, subColor: subColor,
                  background: background, bg1: bg1, bg2: bg2, bgImage: bgImage, mesh: mesh.state, spotY: spotY,
                  locales: locales, format: format)
        }
        set {
            pages = newValue.pages; exportDevices = newValue.exportDevices; style = newValue.style
            showText = newValue.showText; showSub = newValue.showSub; framed = newValue.framed
            finish = newValue.finish; shadow = newValue.shadow
            headline = newValue.headline; subSize = newValue.subSize; subColor = newValue.subColor
            background = newValue.background; bg1 = newValue.bg1; bg2 = newValue.bg2; bgImage = newValue.bgImage
            mesh.state = newValue.mesh; spotY = newValue.spotY
            locales = newValue.locales; format = newValue.format
            if !locales.contains(locale) { locale = primary }
            if let s = selected, !pages.contains(where: { $0.id == s }) { selected = nil }
        }
    }
}

extension BatchModel {
    struct State: Equatable {
        var items: [BatchItem], settings: PipelineSettings
        static func == (a: State, b: State) -> Bool { a.settings == b.settings && a.items.map(\.id) == b.items.map(\.id) }
    }
    var state: State {
        get { State(items: items, settings: settings) }
        set {
            items = newValue.items
            settings = newValue.settings
            selection.formIntersection(items.map(\.id))
            if selection.isEmpty, let first = items.first { selection = [first.id] }
            let stale = items.filter(\.busy).map(\.id)
            if !stale.isEmpty { process(stale) }
        }
    }
}

extension BackgroundModel {
    var state: CutoutOptions {
        get { options }
        set { options = newValue }
    }
}

extension ColorModel {
    struct State: Equatable { var current: RGB, against: RGB, history: [RGB] }
    var state: State {
        get { State(current: current, against: against, history: history) }
        set { current = newValue.current; against = newValue.against; history = newValue.history }
    }
}

extension SVGModel {
    struct State: Equatable { var source: String, background: Int, name: String }
    var state: State {
        get { State(source: source, background: background, name: name) }
        set { source = newValue.source; background = newValue.background; name = newValue.name }
    }
}

extension FaviconModel {
    struct State: Equatable {
        var source: Source, glyph: String, glyphColor: Color, family: String, member: String
        var tile: Bool, tileFill: Fill, tileColor: Color, tileColor2: Color, mesh: MeshModel.State
        var radius: Double, padding: Double, title: String
        var image: CGImage?, imageName: String
    }
    var state: State {
        get {
            State(source: source, glyph: glyph, glyphColor: glyphColor, family: family, member: member,
                  tile: tile, tileFill: tileFill, tileColor: tileColor, tileColor2: tileColor2, mesh: mesh.state, radius: radius, padding: padding, title: title,
                  image: image, imageName: imageName)
        }
        set {
            source = newValue.source; glyph = newValue.glyph; glyphColor = newValue.glyphColor
            family = newValue.family; member = newValue.member
            tile = newValue.tile; tileFill = newValue.tileFill; tileColor = newValue.tileColor
            tileColor2 = newValue.tileColor2; mesh.state = newValue.mesh; radius = newValue.radius
            padding = newValue.padding; title = newValue.title
            image = newValue.image; imageName = newValue.imageName
        }
    }
}

extension IconModel {
    struct State: Equatable { var macShape: Bool, fill: Bool, inset: Double, background: Color, useBackground: Bool }
    var state: State {
        get { State(macShape: macShape, fill: fill, inset: inset, background: background, useBackground: useBackground) }
        set {
            macShape = newValue.macShape; fill = newValue.fill; inset = newValue.inset
            background = newValue.background; useBackground = newValue.useBackground
        }
    }
}

/// Naming rules only: the file list follows renames on disk, which have their own undo.
extension RenameModel {
    struct State: Equatable {
        var base: Base, pattern: String, prefix: String, suffix: String, trimStart: Double, trimEnd: Double
        var find: String, replace: String, regex: Bool, caseStyle: CaseStyle, lowercaseExt: Bool
        var start: Double, padding: Double, step: Double, sort: Sort
    }
    var state: State {
        get {
            State(base: base, pattern: pattern, prefix: prefix, suffix: suffix, trimStart: trimStart, trimEnd: trimEnd,
                  find: find, replace: replace, regex: regex, caseStyle: caseStyle, lowercaseExt: lowercaseExt,
                  start: start, padding: padding, step: step, sort: sort)
        }
        set {
            base = newValue.base; pattern = newValue.pattern; prefix = newValue.prefix; suffix = newValue.suffix
            trimStart = newValue.trimStart; trimEnd = newValue.trimEnd
            find = newValue.find; replace = newValue.replace; regex = newValue.regex
            caseStyle = newValue.caseStyle; lowercaseExt = newValue.lowercaseExt
            start = newValue.start; padding = newValue.padding; step = newValue.step; sort = newValue.sort
        }
    }
}
