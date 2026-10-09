import AppKit
import EditorCore

final class RootView: NSView, AppUI {
    override var isFlipped: Bool { true }
    let model: AppModel
    let toolbar = ToolbarView()
    let columnRow = NSStackView()
    let left = ColumnView(group: 0)
    let right = ColumnView(group: 1)
    let status = StatusBarView()
    private let findPanel = FindPanelController()
    private var previewToken = UUID()
    private var focusedDocument: UUID?

    init(model: AppModel) {
        self.model = model
        super.init(frame: NSRect(x: 0, y: 0, width: 1100, height: 740))
        toolbar.model = model
        left.model = model
        right.model = model
        status.model = model
        columnRow.orientation = .horizontal
        columnRow.distribution = .fillEqually
        columnRow.spacing = 0
        for view in [toolbar, columnRow, status] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 34),
            columnRow.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            columnRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            columnRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            columnRow.bottomAnchor.constraint(equalTo: status.topAnchor),
            status.leadingAnchor.constraint(equalTo: leadingAnchor),
            status.trailingAnchor.constraint(equalTo: trailingAnchor),
            status.bottomAnchor.constraint(equalTo: bottomAnchor),
            status.heightAnchor.constraint(equalToConstant: 28)
        ])
        columnRow.addArrangedSubview(left)
        NotificationCenter.default.addObserver(self, selector: #selector(documentEdited(_:)), name: .editorEdited, object: nil)
        registerForDraggedTypes([.fileURL, .string])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func reload() {
        applyAppearance()
        toolbar.reload()
        if model.split {
            if right.superview == nil { columnRow.addArrangedSubview(right) }
        } else {
            right.removeFromSuperview()
        }
        left.reload()
        right.reload()
        status.reload()
        focusActiveEditor()
        if model.findOpen, let window {
            findPanel.show(relativeTo: window, model: model)
        } else {
            findPanel.hide()
        }
        window?.title = model.windowTitle
        NotificationCenter.default.post(name: .rebuildEditorMenu, object: nil)
        schedulePreview()
    }

    func refreshDisplay() {
        left.refreshDisplay()
        right.refreshDisplay()
        status.reload()
    }

    private func focusActiveEditor() {
        let id = model.groups[model.activeGroup].activeID
        guard id != focusedDocument else { return }
        focusedDocument = id
        let column = model.activeGroup == 1 ? right : left
        guard let textView = column.currentTextView else { return }
        window?.makeFirstResponder(textView)
    }

    func noteEdit(_ id: UUID) {
        left.noteEdit(id)
        right.noteEdit(id)
        window?.title = model.windowTitle
        if model.activeDocument()?.id == id { schedulePreview() }
    }

    func updateCursor() {
        status.updateCursor()
    }

    @objc private func documentEdited(_ notification: Notification) {
        guard let id = notification.object as? UUID else { return }
        noteEdit(id)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        model.openURLs(urls)
        return true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    private func applyAppearance() {
        let appearance = NSAppearance(named: model.theme == .dark ? .darkAqua : .aqua)
        self.appearance = appearance
        window?.appearance = appearance
    }

    private func schedulePreview() {
        let token = UUID()
        previewToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self, self.previewToken == token else { return }
            guard let document = self.model.activeDocument(), document.language == .markdown, document.showPreview else { return }
            let column = self.model.activeGroup == 1 ? self.right : self.left
            let html: String
            if document.text.count > 400_000 {
                html = "<p>文件较大，预览已暂停。</p>"
            } else {
                html = MarkdownHTML.render(document.text)
            }
            column.preview.update(
                body: html,
                theme: self.model.theme,
                baseURL: document.path?.deletingLastPathComponent(),
                anchorLine: column.visibleEditorLine()
            )
        }
    }
}

final class ToolButton: NSButton {
    var isChosen = false { didSet { restyle() } }
    private var hovering = false

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: size.width + 8, height: 24)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        restyle()
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        restyle()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        restyle()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.cornerRadius = 4
        restyle()
    }

    override func mouseDown(with event: NSEvent) {
        PlainTextView.commitMarkedPinyin()
        super.mouseDown(with: event)
    }

    private func restyle() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let color: NSColor
        if isChosen {
            color = dark
                ? NSColor.white.withAlphaComponent(hovering ? 0.14 : 0.10)
                : NSColor.black.withAlphaComponent(hovering ? 0.08 : 0.06)
        } else if hovering {
            color = dark ? NSColor.white.withAlphaComponent(0.07) : NSColor.black.withAlphaComponent(0.045)
        } else {
            color = .clear
        }
        layer?.backgroundColor = color.cgColor
        let textColor: NSColor = isEnabled ? .labelColor : .disabledControlTextColor
        contentTintColor = textColor
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: font ?? NSFont.systemFont(ofSize: 12),
            .foregroundColor: textColor
        ])
    }

    override var isEnabled: Bool {
        didSet { restyle() }
    }
}

final class ToolbarView: NSView {
    weak var model: AppModel?
    private var buttons: [String: ToolButton] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 2
        row.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        func add(_ key: String, _ symbol: String, _ tip: String, _ action: Selector) {
            let button = ToolButton()
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
            button.title = tip
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.font = .systemFont(ofSize: 12)
            button.isBordered = false
            button.controlSize = .small
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = tip
            button.target = self
            button.action = action
            button.setContentHuggingPriority(.required, for: .horizontal)
            buttons[key] = button
            row.addArrangedSubview(button)
        }
        add("new", "plus", "新建", #selector(newFile))
        add("open", "folder", "打开", #selector(openFile))
        add("save", "square.and.arrow.down", "保存", #selector(saveFile))
        row.addArrangedSubview(separator())
        add("undo", "arrow.uturn.backward", "撤销", #selector(undo))
        add("redo", "arrow.uturn.forward", "重做", #selector(redo))
        row.addArrangedSubview(separator())
        add("find", "magnifyingglass", "查找", #selector(find))
        add("replace", "arrow.left.arrow.right", "替换", #selector(replace))
        row.addArrangedSubview(separator())
        add("wrap", "text.alignleft", "自动换行", #selector(wrap))
        add("preview", "eye", "Markdown 预览", #selector(preview))
        row.addArrangedSubview(NSView())
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func reload() {
        guard let model else { return }
        let hasDoc = model.activeDocument() != nil
        buttons["save"]?.isEnabled = hasDoc
        buttons["find"]?.isEnabled = hasDoc
        buttons["replace"]?.isEnabled = hasDoc
        let markdown = model.activeDocument()?.language == .markdown
        buttons["preview"]?.isEnabled = markdown
        tint("wrap", model.wordWrap)
        tint("preview", markdown && (model.activeDocument()?.showPreview ?? false))
        buttons["preview"]?.image = NSImage(
            systemSymbolName: (model.activeDocument()?.showPreview ?? false) ? "eye.fill" : "eye",
            accessibilityDescription: "Markdown 预览"
        )
    }

    private func tint(_ key: String, _ active: Bool) {
        buttons[key]?.isChosen = active
    }

    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 1).isActive = true
        box.heightAnchor.constraint(equalToConstant: 16).isActive = true
        return box
    }

    @objc private func newFile() { model?.newFile() }
    @objc private func openFile() { model?.openPanel() }
    @objc private func saveFile() { model?.saveActive() }
    @objc private func undo() { model?.sendEdit(Selector(("undo:"))) }
    @objc private func redo() { model?.sendEdit(Selector(("redo:"))) }
    @objc private func find() { model?.openFind(replace: false) }
    @objc private func replace() { model?.openFind(replace: true) }
    @objc private func wrap() { model?.wordWrap.toggle() }
    @objc private func preview() { model?.togglePreview() }
}

final class PreviewSplitter: NSView {
    var onDragTo: ((CGFloat) -> Void)?

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let color = dark ? NSColor(white: 0.28, alpha: 1) : NSColor(calibratedWhite: 0.78, alpha: 1)
        color.setFill()
        NSRect(x: floor((bounds.width - 1) / 2), y: 0, width: 1, height: bounds.height).fill()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        onDragTo?(event.locationInWindow.x)
        while true {
            guard let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }
            onDragTo?(next.locationInWindow.x)
            if next.type == .leftMouseUp { break }
        }
    }
}

final class ColumnView: NSView {
    override var isFlipped: Bool { true }
    let group: Int
    weak var model: AppModel?
    let preview = PreviewController()
    private let tabs = NSStackView()
    private let tabBar = NSView()
    private let tabSeparator = NSView()
    private let editorStage = NSView()
    private let empty = NSTextField(labelWithString: "拖入文件，或从文件菜单打开")
    private var hosts: [UUID: EditorHost] = [:]
    private var tabButtons: [UUID: TabButton] = [:]
    private let previewSeparator = PreviewSplitter()
    private var previewWidth: NSLayoutConstraint!
    private var separatorWidth: NSLayoutConstraint!
    private var previewFraction: CGFloat = 0.46

    init(group: Int) {
        self.group = group
        super.init(frame: .zero)
        tabBar.wantsLayer = true
        tabSeparator.wantsLayer = true
        tabSeparator.translatesAutoresizingMaskIntoConstraints = false
        tabBar.addSubview(tabSeparator)
        tabs.orientation = .horizontal
        tabs.alignment = .centerY
        tabs.spacing = 6
        tabs.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        tabs.translatesAutoresizingMaskIntoConstraints = false
        tabBar.addSubview(tabs)
        empty.alignment = .center
        empty.textColor = .secondaryLabelColor
        preview.webView.translatesAutoresizingMaskIntoConstraints = false
        previewSeparator.wantsLayer = true
        previewSeparator.translatesAutoresizingMaskIntoConstraints = false
        for view in [tabBar, editorStage, previewSeparator, preview.webView, empty] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let width = preview.webView.widthAnchor.constraint(equalToConstant: 0)
        let separator = previewSeparator.widthAnchor.constraint(equalToConstant: 0)
        previewWidth = width
        separatorWidth = separator
        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: 36),
            tabs.leadingAnchor.constraint(equalTo: tabBar.leadingAnchor),
            tabs.centerYAnchor.constraint(equalTo: tabBar.centerYAnchor),
            tabs.heightAnchor.constraint(equalToConstant: 26),
            tabSeparator.leadingAnchor.constraint(equalTo: tabBar.leadingAnchor),
            tabSeparator.trailingAnchor.constraint(equalTo: tabBar.trailingAnchor),
            tabSeparator.bottomAnchor.constraint(equalTo: tabBar.bottomAnchor),
            tabSeparator.heightAnchor.constraint(equalToConstant: 1),
            editorStage.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            editorStage.leadingAnchor.constraint(equalTo: leadingAnchor),
            editorStage.bottomAnchor.constraint(equalTo: bottomAnchor),
            editorStage.trailingAnchor.constraint(equalTo: previewSeparator.leadingAnchor),
            previewSeparator.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            previewSeparator.bottomAnchor.constraint(equalTo: bottomAnchor),
            previewSeparator.trailingAnchor.constraint(equalTo: preview.webView.leadingAnchor),
            separator,
            preview.webView.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            preview.webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            preview.webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            width,
            empty.centerXAnchor.constraint(equalTo: editorStage.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: editorStage.centerYAnchor)
        ])
        previewSeparator.onDragTo = { [weak self] x in
            self?.placeSplitter(windowX: x)
        }
        preview.onScrollLine = { [weak self] line in
            self?.scrollEditor(to: line)
        }
        registerForDraggedTypes([.string, .fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func reload() {
        guard let model else { return }
        let ids = model.groups[group].tabIDs
        for id in hosts.keys where !ids.contains(id) {
            model.registerEditor(group: group, id: id, view: nil)
            hosts[id]?.detach()
            hosts[id]?.container.removeFromSuperview()
            hosts[id] = nil
        }
        for id in ids {
            guard hosts[id] == nil, let document = model.documents[id] else { continue }
            let host = EditorHost(document: document, model: model, group: group)
            hosts[id] = host
            host.container.translatesAutoresizingMaskIntoConstraints = false
            editorStage.addSubview(host.container)
            NSLayoutConstraint.activate([
                host.container.leadingAnchor.constraint(equalTo: editorStage.leadingAnchor),
                host.container.trailingAnchor.constraint(equalTo: editorStage.trailingAnchor),
                host.container.topAnchor.constraint(equalTo: editorStage.topAnchor),
                host.container.bottomAnchor.constraint(equalTo: editorStage.bottomAnchor)
            ])
        }
        let active = model.groups[group].activeID
        for (id, host) in hosts {
            host.container.isHidden = id != active
            host.onVisibleLine = { [weak self, weak host] line in
                guard let self, let host, let model = self.model else { return }
                guard host.document.language == .markdown, host.document.showPreview else { return }
                guard model.activeGroup == self.group, model.groups[self.group].activeID == host.document.id else { return }
                self.preview.scrollToLine(line)
            }
        }
        editorStage.layoutSubtreeIfNeeded()
        if let active, let host = hosts[active], !host.container.isHidden {
            host.container.layoutSubtreeIfNeeded()
            host.apply(wordWrap: model.wordWrap, theme: model.theme)
        }
        for (id, host) in hosts where id != active {
            host.apply(wordWrap: model.wordWrap, theme: model.theme)
        }
        let refreshID = active
        DispatchQueue.main.async { [weak self] in
            guard let self, let model = self.model, let refreshID, let host = self.hosts[refreshID] else { return }
            guard model.groups[self.group].activeID == refreshID else { return }
            host.container.layoutSubtreeIfNeeded()
            host.updateWrapWidth(wordWrap: model.wordWrap)
        }
        rebuildTabs(ids: ids, active: active)
        let document = active.flatMap { model.documents[$0] }
        applyPreviewLayout(document: document)
        empty.isHidden = active != nil
        editorStage.isHidden = active == nil
    }

    func refreshDisplay() {
        guard let model else { return }
        for host in hosts.values {
            host.apply(wordWrap: model.wordWrap, theme: model.theme)
        }
    }

    var currentTextView: NSTextView? {
        guard let id = model?.groups[group].activeID else { return nil }
        return hosts[id]?.textView
    }

    func noteEdit(_ id: UUID) {
        guard let document = model?.documents[id] else { return }
        tabButtons[id]?.setDirty(document.dirty)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        paintTabBar()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paintTabBar()
    }

    private func paintTabBar() {
        tabBar.wantsLayer = true
        tabSeparator.wantsLayer = true
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        tabBar.layer?.backgroundColor = (dark
            ? NSColor(white: 0.18, alpha: 1)
            : NSColor(calibratedWhite: 0.95, alpha: 1)).cgColor
        tabSeparator.layer?.backgroundColor = (dark
            ? NSColor(white: 0.30, alpha: 1)
            : NSColor(calibratedWhite: 0.78, alpha: 1)).cgColor
    }

    override func layout() {
        super.layout()
        applyPreviewLayout(document: currentDocument())
        guard !inLiveResize else { return }
        hosts.values.forEach {
            $0.scrollView.tile()
            $0.updateWrapWidth(wordWrap: model?.wordWrap)
        }
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        hosts.values.forEach {
            $0.scrollView.tile()
            $0.updateWrapWidth(wordWrap: model?.wordWrap)
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let model else { return false }
        let pasteboard = sender.draggingPasteboard
        if let value = pasteboard.string(forType: .string), value.hasPrefix("tab:") {
            let parts = value.split(separator: ":")
            guard parts.count == 3, let from = Int(parts[1]), let id = UUID(uuidString: String(parts[2])) else { return false }
            model.moveTab(id: id, from: from, to: group, index: model.groups[group].tabIDs.count)
            return true
        }
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        model.openURLs(urls)
        return true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if !previewSeparator.isHidden {
            let local = convert(point, from: superview)
            let splitterPoint = previewSeparator.convert(local, from: self)
            if previewSeparator.bounds.insetBy(dx: -8, dy: 0).contains(splitterPoint) {
                return previewSeparator
            }
        }
        return super.hitTest(point)
    }

    private func currentDocument() -> EditorDocument? {
        guard let model, let active = model.groups[group].activeID else { return nil }
        return model.documents[active]
    }

    func visibleEditorLine() -> Int {
        guard let id = model?.groups[group].activeID, let host = hosts[id] else { return 1 }
        return host.firstVisibleLine()
    }

    private func scrollEditor(to line: Int) {
        guard let model, model.activeGroup == group else { return }
        guard let id = model.groups[group].activeID, let host = hosts[id] else { return }
        guard host.document.language == .markdown, host.document.showPreview else { return }
        host.scrollToLine(line)
    }

    private func placeSplitter(windowX: CGFloat) {
        guard bounds.width > 2, separatorWidth.constant > 0 else { return }
        let localX = convert(NSPoint(x: windowX, y: 0), from: nil).x
        let width = bounds.width - localX
        let maxPreview = max(160, bounds.width - 220 - separatorWidth.constant)
        let next = min(max(160, width), maxPreview)
        previewFraction = next / bounds.width
        previewWidth.constant = next
    }

    private func applyPreviewLayout(document: EditorDocument?) {
        guard let model else { return }
        let show = document?.language == .markdown && document?.showPreview == true && model.activeGroup == group
        preview.webView.isHidden = !show
        previewSeparator.isHidden = !show
        separatorWidth.constant = show ? 6 : 0
        if show, bounds.width > 2 {
            let maxPreview = max(160, bounds.width - 220 - 6)
            let wanted = bounds.width * previewFraction
            previewWidth.constant = min(max(160, wanted), maxPreview)
        } else {
            previewWidth.constant = 0
        }
        previewSeparator.needsDisplay = true
    }

    private func rebuildTabs(ids: [UUID], active: UUID?) {
        tabs.arrangedSubviews.forEach {
            tabs.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        tabButtons.removeAll()
        guard let model else { return }
        for (index, id) in ids.enumerated() {
            guard let document = model.documents[id] else { continue }
            let button = TabButton(document: document, group: group, index: index, selected: id == active && model.activeGroup == group)
            button.onSelect = { [weak model] in model?.selectTab(group: self.group, id: id) }
            button.onClose = { [weak model] in model?.close(id: id) }
            tabButtons[id] = button
            tabs.addArrangedSubview(button)
        }
    }
}

final class TabButton: NSView, NSDraggingSource {
    let documentID: UUID
    let group: Int
    let index: Int
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    private let title = NSTextField(labelWithString: "")
    private let dot = NSView()
    private let close = NSButton()

    init(document: EditorDocument, group: Int, index: Int, selected: Bool) {
        self.documentID = document.id
        self.group = group
        self.index = index
        super.init(frame: NSRect(x: 0, y: 0, width: 140, height: 26))
        wantsLayer = true
        layer?.cornerRadius = 6
        title.stringValue = document.name
        title.lineBreakMode = .byTruncatingMiddle
        title.font = .systemFont(ofSize: 12)
        title.translatesAutoresizingMaskIntoConstraints = false
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        dot.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.isHidden = !document.dirty
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭")
        close.isBordered = false
        close.target = self
        close.action = #selector(closeTab)
        close.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)
        addSubview(title)
        addSubview(close)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 88),
            widthAnchor.constraint(lessThanOrEqualToConstant: 180),
            heightAnchor.constraint(equalToConstant: 26),
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
            title.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            close.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 4),
            close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            close.centerYAnchor.constraint(equalTo: centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 14)
        ])
        layer?.backgroundColor = (selected ? NSColor.controlBackgroundColor : NSColor.black.withAlphaComponent(0.06)).cgColor
        layer?.borderWidth = selected ? 1 : 0
        layer?.borderColor = NSColor.separatorColor.cgColor
        toolTip = document.path?.path ?? document.name
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func setDirty(_ dirty: Bool) { dot.isHidden = !dirty }

    @objc private func closeTab() {
        PlainTextView.commitMarkedPinyin()
        onClose?()
    }

    override func mouseDown(with event: NSEvent) {
        PlainTextView.commitMarkedPinyin()
        onSelect?()
    }

    override func mouseDragged(with event: NSEvent) {
        let item = NSPasteboardItem()
        item.setString("tab:\(group):\(documentID.uuidString)", forType: .string)
        let dragging = NSDraggingItem(pasteboardWriter: item)
        dragging.setDraggingFrame(bounds, contents: nil)
        beginDraggingSession(with: [dragging], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
}

final class FindPanelController: NSObject, NSWindowDelegate {
    let panel: NSPanel
    let bar = FindBarView()
    private weak var model: AppModel?
    private var closing = false
    private var lastFocus = -1

    override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 116),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.contentView = bar
        panel.title = "查找"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.becomesKeyOnlyIfNeeded = false
        panel.delegate = self
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53, self.panel.isVisible else { return event }
            guard event.window === self.panel || self.panel.isKeyWindow else { return event }
            if let editor = self.panel.firstResponder as? NSTextView, editor.hasMarkedText() {
                return event
            }
            self.model?.findOpen = false
            return nil
        }
    }

    func show(relativeTo window: NSWindow, model: AppModel) {
        self.model = model
        let replace = model.findShowsReplace
        bar.reload(model)
        panel.title = replace ? "替换" : "查找"
        let height: CGFloat = replace ? 152 : 116
        panel.setContentSize(NSSize(width: 400, height: height))
        if let parent = panel.parent {
            parent.removeChildWindow(panel)
        }
        let opening = !panel.isVisible
        let focusNow = model.findFocus != lastFocus
        lastFocus = model.findFocus
        if opening || focusNow {
            panel.makeKeyAndOrderFront(nil)
            placeInWindow(window)
            bar.focus()
        } else if !panel.isVisible {
            panel.orderFront(nil)
            placeInWindow(window)
        }
    }

    private func placeInWindow(_ window: NSWindow) {
        let size = panel.frame.size
        let parent = window.frame
        guard parent.width > 1, parent.height > 1, size.width > 1, size.height > 1 else { return }
        panel.setFrame(NSRect(
            x: round(parent.midX - size.width / 2),
            y: round(parent.midY - size.height / 2),
            width: size.width,
            height: size.height
        ), display: true)
    }

    func hide() {
        guard !closing else { return }
        closing = true
        let parent = panel.parent
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        parent?.makeKey()
        closing = false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !closing else { return true }
        model?.findOpen = false
        return false
    }
}

final class FindBarView: NSView {
    weak var model: AppModel?
    private let query = NSTextField()
    private let replacement = NSTextField()
    private let status = NSTextField(labelWithString: "")
    private let matchCase = NSButton(checkboxWithTitle: "区分大小写", target: nil, action: nil)
    private let wholeWord = NSButton(checkboxWithTitle: "全字匹配", target: nil, action: nil)
    private let replaceRow = NSStackView()
    private let replaceOneButton = NSButton()
    private let replaceAllButton = NSButton()
    private var suppress = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        query.placeholderString = "查找"
        replacement.placeholderString = "替换为"
        query.delegate = self
        replacement.delegate = self
        matchCase.target = self
        matchCase.action = #selector(optionChanged)
        wholeWord.target = self
        wholeWord.action = #selector(optionChanged)
        matchCase.controlSize = .small
        wholeWord.controlSize = .small
        matchCase.font = .systemFont(ofSize: 12)
        wholeWord.font = .systemFont(ofSize: 12)
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        let findRow = labeledRow("查找", query)
        replaceRow.orientation = .horizontal
        replaceRow.spacing = 8
        replaceRow.alignment = .centerY
        let replaceLabel = NSTextField(labelWithString: "替换")
        replaceLabel.font = .systemFont(ofSize: 12)
        replaceLabel.alignment = .right
        replaceLabel.widthAnchor.constraint(equalToConstant: 36).isActive = true
        replaceRow.addArrangedSubview(replaceLabel)
        replaceRow.addArrangedSubview(replacement)
        let options = NSStackView()
        options.orientation = .horizontal
        options.spacing = 12
        options.addArrangedSubview(matchCase)
        options.addArrangedSubview(wholeWord)
        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.spacing = 6
        actions.alignment = .centerY
        actions.addArrangedSubview(button("上一个", #selector(previous)))
        actions.addArrangedSubview(button("下一个", #selector(next)))
        configure(replaceOneButton, title: "替换", action: #selector(replaceOne))
        configure(replaceAllButton, title: "全部替换", action: #selector(replaceAll))
        actions.addArrangedSubview(replaceOneButton)
        actions.addArrangedSubview(replaceAllButton)
        actions.addArrangedSubview(status)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(findRow)
        stack.addArrangedSubview(replaceRow)
        stack.addArrangedSubview(options)
        stack.addArrangedSubview(actions)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            findRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 12),
            findRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -12),
            replaceRow.leadingAnchor.constraint(equalTo: findRow.leadingAnchor),
            replaceRow.trailingAnchor.constraint(equalTo: findRow.trailingAnchor),
            replacement.widthAnchor.constraint(equalTo: query.widthAnchor)
        ])
    }

    private func labeledRow(_ title: String, _ field: NSTextField) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 36).isActive = true
        row.addArrangedSubview(label)
        row.addArrangedSubview(field)
        return row
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func reload(_ model: AppModel) {
        self.model = model
        suppress = true
        if query.stringValue != model.findQuery { query.stringValue = model.findQuery }
        if replacement.stringValue != model.findReplacement { replacement.stringValue = model.findReplacement }
        matchCase.state = model.findMatchCase ? .on : .off
        wholeWord.state = model.findWholeWord ? .on : .off
        replacement.isHidden = !model.findShowsReplace
        replaceRow.isHidden = !model.findShowsReplace
        replaceOneButton.isHidden = !model.findShowsReplace
        replaceAllButton.isHidden = !model.findShowsReplace
        status.stringValue = model.findStatus
        suppress = false
    }

    func focus() { window?.makeFirstResponder(query) }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        return button
    }

    private func configure(_ button: NSButton, title: String, action: Selector) {
        button.title = title
        button.target = self
        button.action = action
        button.bezelStyle = .rounded
        button.controlSize = .small
    }

    @objc private func optionChanged() {
        guard !suppress else { return }
        model?.findMatchCase = matchCase.state == .on
        model?.findWholeWord = wholeWord.state == .on
    }

    @objc private func previous() { run { $0.findNext(reverse: true) } }
    @objc private func next() { run { $0.findNext(reverse: false) } }
    @objc private func replaceOne() { run { $0.replaceCurrent() } }
    @objc private func replaceAll() { run { $0.replaceAll() } }
    @objc private func closeBar() { model?.findOpen = false }

    private func run(_ action: (AppModel) -> Void) {
        guard let model else { return }
        syncFields()
        action(model)
        status.stringValue = model.findStatus
    }

    private func syncFields() {
        model?.findQuery = query.stringValue
        model?.findReplacement = replacement.stringValue
    }
}

extension FindBarView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard !suppress else { return }
        syncFields()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            next()
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            closeBar()
            return true
        }
        return false
    }
}

final class StatusBarView: NSView {
    weak var model: AppModel?
    private let cursor = NSTextField(labelWithString: "")
    private let zoom = NSTextField(labelWithString: "100%")
    private let encoding = NSPopUpButton()
    private let language = NSPopUpButton()
    private let eol = NSTextField(labelWithString: "")
    private var suppress = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        cursor.font = .systemFont(ofSize: 11)
        zoom.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        zoom.textColor = .secondaryLabelColor
        eol.font = .systemFont(ofSize: 11)
        eol.textColor = .secondaryLabelColor
        encoding.controlSize = .small
        language.controlSize = .small
        encoding.target = self
        encoding.action = #selector(encodingChanged)
        language.target = self
        language.action = #selector(languageChanged)
        for item in TextEncoding.allCases {
            encoding.addItem(withTitle: item.label)
            encoding.lastItem?.representedObject = item.rawValue
        }
        for item in Language.allCases {
            language.addItem(withTitle: item.label)
            language.lastItem?.representedObject = item.rawValue
        }
        row.addArrangedSubview(cursor)
        row.addArrangedSubview(zoom)
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(encoding)
        row.addArrangedSubview(language)
        row.addArrangedSubview(eol)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        paint()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
    }

    private func paint() {
        wantsLayer = true
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = (dark ? NSColor(white: 0.16, alpha: 1) : NSColor(calibratedWhite: 0.94, alpha: 1)).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func reload() {
        guard let model else { return }
        suppress = true
        updateCursor()
        zoom.stringValue = "\(Int((model.fontSize / 13 * 100).rounded()))%"
        if let document = model.activeDocument() {
            encoding.isEnabled = true
            language.isEnabled = true
            encoding.selectItem(at: TextEncoding.allCases.firstIndex(of: document.encoding) ?? 0)
            language.selectItem(at: Language.allCases.firstIndex(of: document.language) ?? 0)
            eol.stringValue = document.eol.rawValue
        } else {
            encoding.isEnabled = false
            language.isEnabled = false
            eol.stringValue = ""
        }
        suppress = false
    }

    func updateCursor() {
        guard let model else { return }
        if model.activeDocument() == nil {
            cursor.stringValue = "未打开文件"
        } else {
            cursor.stringValue = "行 \(model.cursorLine)，列 \(model.cursorColumn)"
        }
    }

    @objc private func encodingChanged() {
        guard !suppress, let raw = encoding.selectedItem?.representedObject as? String, let value = TextEncoding(rawValue: raw) else { return }
        model?.setEncoding(value)
    }

    @objc private func languageChanged() {
        guard !suppress, let raw = language.selectedItem?.representedObject as? String, let value = Language(rawValue: raw) else { return }
        model?.setLanguage(value)
    }
}

