import AppKit
import EditorCore

final class PlainTextView: NSTextView {
    private(set) var isCommittingPinyin = false
    /// 点进文本后已经收下的拼音。输入法若再贴一次同样的内容，丢掉这一次。
    private var echoToIgnore: String?
    var onTextChange: (() -> Void)?
    var onMagnify: ((CGFloat) -> Void)?

    override func magnify(with event: NSEvent) {
        onMagnify?(event.magnification)
    }

    override func scrollWheel(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) else {
            super.scrollWheel(with: event)
            return
        }
        let delta = event.scrollingDeltaY
        guard abs(delta) > 0.01 else { return }
        if event.hasPreciseScrollingDeltas {
            onMagnify?(delta / 80)
        } else {
            onMagnify?(delta > 0 ? 0.12 : -0.12)
        }
    }

    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }

    override func didChangeText() {
        super.didChangeText()
        onTextChange?()
    }

    override func mouseDown(with event: NSEvent) {
        if hasMarkedText() {
            acceptMarkedPinyin()
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.clickCount != 1
            || flags.contains(.shift) || flags.contains(.command) || flags.contains(.control) {
            super.mouseDown(with: event)
            return
        }
        guard placeCaretOnLine(at: convert(event.locationInWindow, from: nil)) else {
            super.mouseDown(with: event)
            return
        }
    }

    /// 点在某一行的空白处时，把光标放到这一行末尾；点在文字上则交给系统决定具体列。
    private func placeCaretOnLine(at point: NSPoint) -> Bool {
        guard let layoutManager else { return false }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let ns = string as NSString
        if layoutManager.numberOfGlyphs > 0 {
            var onLine = false
            var onGlyphs = false
            layoutManager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs)) { _, used, _, glyphRange, stop in
                let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
                guard local.y >= fragment.minY, local.y < fragment.maxY else { return }
                stop.pointee = true
                onLine = true
                if local.x >= used.minX, local.x <= used.maxX + 2 {
                    onGlyphs = true
                    return
                }
                let chars = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
                var location = local.x < used.minX ? chars.location : NSMaxRange(chars)
                if local.x >= used.minX, location > chars.location, location <= ns.length {
                    let ch = ns.character(at: location - 1)
                    if ch == 10 || ch == 13 { location -= 1 }
                }
                self.setSelectedRange(NSRange(location: min(max(0, location), ns.length), length: 0))
            }
            if onGlyphs { return false }
            if onLine { return true }
        }
        let extra = layoutManager.extraLineFragmentRect
        if extra.height > 0, local.y >= extra.minY, local.y < extra.maxY {
            setSelectedRange(NSRange(location: ns.length, length: 0))
            return true
        }
        return false
    }

    /// 工具栏、菜单或切换标签时，把尚未选定的拼音按普通字母写进当前文档。
    static func commitMarkedPinyin() {
        for window in NSApp.windows {
            guard let content = window.contentView else { continue }
            commitMarkedPinyin(in: content)
        }
    }

    private static func commitMarkedPinyin(in view: NSView) {
        if let textView = view as? PlainTextView {
            textView.acceptMarkedPinyin()
        }
        for subview in view.subviews {
            commitMarkedPinyin(in: subview)
        }
    }

    func acceptMarkedPinyin() {
        guard hasMarkedText(), !isCommittingPinyin else { return }
        let range = markedRange()
        var letters = ""
        var location = 0
        if range.location != NSNotFound,
           let storage = textStorage,
           NSMaxRange(range) <= storage.length {
            letters = (storage.string as NSString).substring(with: range)
            location = range.location
        }
        let plain = plainLetters(letters)
        isCommittingPinyin = true
        unmarkText()
        isCommittingPinyin = false
        guard !plain.isEmpty, let storage = textStorage else { return }
        let ns = storage.string as NSString
        let start = min(location, ns.length)
        let windowLength = min(ns.length - start, (letters as NSString).length + (plain as NSString).length)
        let window = (windowLength > 0
            ? ns.substring(with: NSRange(location: start, length: windowLength))
            : "") as NSString
        if let twice = prefixLength(in: window, matching: plain, copies: 2) {
            storage.replaceCharacters(in: NSRange(location: start, length: twice), with: plain)
        } else if let once = prefixLength(in: window, matching: plain, copies: 1) {
            if window.substring(with: NSRange(location: 0, length: once)) != plain {
                storage.replaceCharacters(in: NSRange(location: start, length: once), with: plain)
            }
        } else {
            storage.replaceCharacters(in: NSRange(location: start, length: 0), with: plain)
        }
        echoToIgnore = plain
    }

    private func prefixLength(in text: NSString, matching plain: String, copies: Int) -> Int? {
        let plainText = plain as NSString
        guard plainText.length > 0, copies > 0 else { return nil }
        let target = plainText.length * copies
        var seen = 0
        var index = 0
        while index < text.length && seen < target {
            let character = text.character(at: index)
            if isPinyinGap(character) {
                index += 1
                continue
            }
            if character != plainText.character(at: seen % plainText.length) {
                return nil
            }
            seen += 1
            index += 1
        }
        return seen == target ? index : nil
    }

    private func isPinyinGap(_ character: unichar) -> Bool {
        switch character {
        case 0x20, 0x09, 0xA0, 0x3000, 0x2006, 0x2009:
            return true
        default:
            return false
        }
    }

    private func plainLetters(_ text: String) -> String {
        String(text.unicodeScalars.filter { scalar in
            switch scalar.value {
            case 0x20, 0x09, 0x0A, 0x0D, 0xA0, 0x3000, 0x2006, 0x2009:
                return false
            default:
                return true
            }
        }.map(Character.init))
    }

    override func keyDown(with event: NSEvent) {
        echoToIgnore = nil
        super.keyDown(with: event)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let incoming = (insertString as? String) ?? (insertString as? NSAttributedString)?.string ?? ""
        if let echo = echoToIgnore, plainLetters(incoming) == echo {
            return
        }
        super.insertText(insertString, replacementRange: replacementRange)
    }
}

final class LayoutWatcher: NSObject, NSLayoutManagerDelegate {
    weak var next: NSLayoutManagerDelegate?
    var onFinished: (() -> Void)?
    var drawingColor: ((Int, NSRangePointer?) -> NSColor?)?
    private var inside = false

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        didCompleteLayoutFor textContainer: NSTextContainer?,
        atEnd layoutFinishedFlag: Bool
    ) {
        guard !inside else { return }
        inside = true
        next?.layoutManager?(layoutManager, didCompleteLayoutFor: textContainer, atEnd: layoutFinishedFlag)
        if layoutFinishedFlag { onFinished?() }
        inside = false
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldUseTemporaryAttributes attrs: [NSAttributedString.Key: Any] = [:],
        forDrawingToScreen toScreen: Bool,
        atCharacterIndex charIndex: Int,
        effectiveRange effectiveCharRange: NSRangePointer?
    ) -> [NSAttributedString.Key: Any]? {
        guard toScreen, let drawingColor else { return attrs }
        let color = drawingColor(charIndex, effectiveCharRange)
        var merged = attrs
        if let color {
            merged[.foregroundColor] = color
        } else {
            merged.removeValue(forKey: .foregroundColor)
        }
        // 一个字一个字取，避免一段纯文本把括号的底色一起盖掉。
        effectiveCharRange?.pointee = NSRange(location: charIndex, length: 1)
        return merged
    }
}

final class LineNumberGutter: NSView {
    weak var textView: NSTextView?
    var theme: AppTheme = .light
    var reportedLineCount = 1

    override var isFlipped: Bool { true }
    private var expandingDisplay = false
    private var cachedStep: CGFloat = 0

    override func setNeedsDisplay(_ invalidRect: NSRect) {
        let full = bounds
        if expandingDisplay || full.isEmpty || invalidRect.equalTo(full) {
            super.setNeedsDisplay(invalidRect)
            return
        }
        expandingDisplay = true
        super.setNeedsDisplay(full)
        expandingDisplay = false
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = theme == .dark
        (dark ? NSColor(white: 0.17, alpha: 1) : NSColor(calibratedWhite: 0.93, alpha: 1)).setFill()
        bounds.fill()
        (dark ? NSColor(white: 0.28, alpha: 1) : NSColor(calibratedWhite: 0.78, alpha: 1)).setFill()
        NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()
        guard let textView else { return }
        let marked = textView.hasMarkedText() || (textView as? PlainTextView)?.isCommittingPinyin == true
        let length = textView.textStorage?.length ?? 0
        let large = length >= Syntax.largeFileLimit
        let string = (large && textView.textContainer?.widthTracksTextView != true) ? ("" as NSString) : (textView.string as NSString)
        let textFont = textView.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let numberFont = NSFont.monospacedDigitSystemFont(ofSize: textFont.pointSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: dark ? NSColor(white: 0.62, alpha: 1) : NSColor(white: 0.32, alpha: 1)
        ]
        func gutterY(_ containerY: CGFloat) -> CGFloat {
            convert(NSPoint(x: 0, y: containerY + textView.textContainerOrigin.y), from: textView).y
        }
        let expected = large ? max(1, reportedLineCount) : (length == 0 ? 1 : 1 + newlineCount(string, upTo: string.length))
        if marked || textView.layoutManager == nil {
            let step = cachedStep > 1 ? cachedStep : max(textFont.ascender - textFont.descender + textFont.leading, 1)
            drawLogicalLines(expected: expected, anchor: gutterY(0), step: step, attributes: attributes)
            return
        }
        guard let layoutManager = textView.layoutManager else { return }
        var step = max(layoutManager.defaultLineHeight(for: textFont), 1)
        var anchor = gutterY(0)
        if large {
            if length > 0 {
                layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: 1))
                let rect = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil, withoutAdditionalLayout: true)
                if rect.height > 1, rect.height < step * 2.5 {
                    step = rect.height
                    anchor = gutterY(rect.minY)
                }
            }
            cachedStep = step
            drawLogicalLines(expected: expected, anchor: anchor, step: step, attributes: attributes)
            return
        }
        if layoutManager.numberOfGlyphs > 0 {
            let rect = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
            if rect.height > 1, rect.height < step * 2.5 {
                step = rect.height
                anchor = gutterY(rect.minY)
            }
        }
        cachedStep = step
        let wrapping = textView.textContainer?.widthTracksTextView == true
        if !wrapping {
            drawLogicalLines(expected: expected, anchor: anchor, step: step, attributes: attributes)
            return
        }
        var drawn: Set<Int> = []
        let glyphs = NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        if glyphs.length > 0 {
            layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, glyphRange, _ in
                let charIndex = layoutManager.characterIndexForGlyph(at: glyphRange.location)
                guard charIndex < string.length else { return }
                let lineChar = string.lineRange(for: NSRange(location: charIndex, length: 0))
                guard charIndex <= lineChar.location else { return }
                let line = 1 + newlineCount(string, upTo: charIndex)
                guard line <= expected else { return }
                let y = gutterY(rect.minY)
                if y > -rect.height && y < self.bounds.height {
                    drawn.insert(line)
                    self.drawNumber("\(line)", top: y, height: rect.height, attributes: attributes)
                }
            }
        }
        if string.length > 0, string.character(at: string.length - 1) == 10, !drawn.contains(expected) {
            let extra = layoutManager.extraLineFragmentRect
            let y = extra.height > 0 ? gutterY(extra.minY) : gutterY(0) + CGFloat(expected - 1) * step
            let height = extra.height > 0 ? extra.height : step
            if y > -height && y < bounds.height {
                drawNumber("\(expected)", top: y, height: height, attributes: attributes)
            }
        }
    }

    private func drawLogicalLines(expected: Int, anchor: CGFloat, step: CGFloat, attributes: [NSAttributedString.Key: Any]) {
        guard expected >= 1, step > 0 else { return }
        let first = max(1, Int(floor(-anchor / step)) + 1)
        var last = Int(ceil((bounds.height - anchor) / step)) + 1
        if last > expected { last = expected }
        guard first <= last else { return }
        for line in first...last {
            let y = anchor + CGFloat(line - 1) * step
            drawNumber("\(line)", top: y, height: step, attributes: attributes)
        }
    }

    private func drawNumber(_ text: String, top: CGFloat, height: CGFloat, attributes: [NSAttributedString.Key: Any]) {
        let label = text as NSString
        let size = label.size(withAttributes: attributes)
        let y = top + max(0, (height - size.height) / 2)
        label.draw(in: NSRect(x: bounds.width - size.width - 10, y: y, width: size.width + 1, height: max(size.height, 1)), withAttributes: attributes)
    }
}

private func longestLineLength(_ text: NSString) -> Int {
    var longest = 0
    var run = 0
    var index = 0
    while index < text.length {
        let character = text.character(at: index)
        if character == 10 || character == 13 {
            if run > longest { longest = run }
            run = 0
            if character == 13, index + 1 < text.length, text.character(at: index + 1) == 10 {
                index += 1
            }
        } else {
            run += 1
        }
        index += 1
    }
    return max(longest, run)
}

private func wrappedLineCount(_ text: NSString, columns: Int) -> Int {
    let columns = max(1, columns)
    var total = 0
    var run = 0
    var index = 0
    func finishLine() {
        total += run == 0 ? 1 : (run + columns - 1) / columns
        run = 0
    }
    while index < text.length {
        let character = text.character(at: index)
        if character == 10 || character == 13 {
            finishLine()
            if character == 13, index + 1 < text.length, text.character(at: index + 1) == 10 {
                index += 1
            }
        } else {
            run += 1
        }
        index += 1
    }
    if text.length == 0 { return 1 }
    let last = text.character(at: text.length - 1)
    if last == 10 || last == 13 {
        total += 1
    } else {
        finishLine()
    }
    return max(1, total)
}

private func newlineCount(_ text: NSString, upTo location: Int) -> Int {
    let end = min(max(0, location), text.length)
    var count = 0
    var index = 0
    while index < end {
        if text.character(at: index) == 10 { count += 1 }
        index += 1
    }
    return count
}

final class EditorHost: NSObject, NSTextViewDelegate {
    let container = NSView()
    let gutter = LineNumberGutter()
    let scrollView = NSScrollView()
    let textView: NSTextView
    let document: EditorDocument
    let group: Int
    let model: AppModel
    var onVisibleLine: ((Int) -> Void)?
    private var layoutWatcher: LayoutWatcher?
    private var colorGeneration = 0
    private var braceSpans: [NSRange] = []
    private var snapshot: NSString = ""
    private var snapshotGeneration = Int.min
    private var measuredGeneration = Int.min
    private var measuredWrap = false
    private var measuredWidth: CGFloat = -1
    private var measuredColumns = 0
    private var measuredLines = 0
    private var gutterWidthConstraint: NSLayoutConstraint?
    private var scrollSyncWork: DispatchWorkItem?
    private var suppressScrollSync = false
    private var lastSyncedLine = 0

    init(document: EditorDocument, model: AppModel, group: Int) {
        self.document = document
        self.model = model
        self.group = group

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.automaticallyAdjustsContentInsets = false

        let editor = PlainTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        editor.minSize = NSSize(width: 0, height: 0)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = []
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.usesFindBar = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticDataDetectionEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.enabledTextCheckingTypes = 0
        editor.font = document.buffer.font
        editor.textColor = .labelColor
        editor.insertionPointColor = .controlAccentColor
        editor.backgroundColor = .textBackgroundColor
        editor.drawsBackground = true
        editor.textContainerInset = NSSize(width: 4, height: 4)
        editor.textContainer?.lineFragmentPadding = 4
        editor.isEditable = true
        editor.isSelectable = true
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.typingAttributes = [.font: document.buffer.font]
        textView = editor
        gutter.textView = editor
        gutter.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(gutter)
        container.addSubview(scrollView)
        let gutterWidth = gutter.widthAnchor.constraint(equalToConstant: 52)
        gutterWidthConstraint = gutterWidth
        NSLayoutConstraint.activate([
            gutter.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            gutter.topAnchor.constraint(equalTo: container.topAnchor),
            gutter.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            gutterWidth,
            scrollView.leadingAnchor.constraint(equalTo: gutter.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        scrollView.hasVerticalRuler = false
        scrollView.rulersVisible = false
        scrollView.documentView = editor
        let largeFile = document.buffer.storage.length >= Syntax.largeFileLimit
        editor.layoutManager?.allowsNonContiguousLayout = largeFile
        editor.layoutManager?.replaceTextStorage(document.buffer.storage)
        scrollView.contentView.postsBoundsChangedNotifications = true

        super.init()
        editor.delegate = self
        editor.onTextChange = { [weak self] in
            self?.gutter.needsDisplay = true
        }
        editor.onMagnify = { [weak self] delta in
            self?.model.zoom(by: delta)
        }
        let watcher = LayoutWatcher()
        watcher.next = editor.layoutManager?.delegate
        watcher.onFinished = { [weak self] in
            self?.gutter.needsDisplay = true
        }
        watcher.drawingColor = { [weak self] index, range in
            guard let self else { return nil }
            return Highlighter.drawingColor(
                text: self.currentText(),
                language: self.document.language,
                generation: self.colorGeneration,
                at: index,
                effectiveRange: range
            )
        }
        editor.layoutManager?.delegate = watcher
        layoutWatcher = watcher
        NotificationCenter.default.addObserver(self, selector: #selector(redrawRuler), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        model.registerEditor(group: group, id: document.id, view: editor)
        apply(wordWrap: model.wordWrap, theme: model.theme)
        Highlighter.apply(storage: document.buffer.storage, language: document.language)
    }

    func detach() {
        if let manager = textView.layoutManager {
            document.buffer.storage.removeLayoutManager(manager)
        }
        NotificationCenter.default.removeObserver(self)
    }

    func apply(wordWrap: Bool, theme: AppTheme) {
        colorGeneration &+= 1
        let appearance = NSAppearance(named: theme == .dark ? .darkAqua : .aqua)
        textView.appearance = appearance
        scrollView.appearance = appearance
        let textColor: NSColor = theme == .dark ? .white : .black
        textView.backgroundColor = theme == .dark ? NSColor(white: 0.12, alpha: 1) : .white
        scrollView.backgroundColor = textView.backgroundColor
        textView.textColor = textColor
        textView.insertionPointColor = textColor
        let font = NSFont.monospacedSystemFont(ofSize: model.fontSize, weight: .regular)
        document.buffer.font = font
        document.buffer.applyFont()
        textView.font = font
        textView.typingAttributes = [.font: font]
        gutter.theme = theme
        gutter.needsDisplay = true
        guard let container = textView.textContainer else { return }
        container.widthTracksTextView = wordWrap
        updateWrapWidth(wordWrap: wordWrap)
    }

    func updateWrapWidth(wordWrap: Bool? = nil) {
        guard let container = textView.textContainer, let layoutManager = textView.layoutManager else { return }
        guard !textView.hasMarkedText() else { return }
        if (textView as? PlainTextView)?.isCommittingPinyin == true { return }
        updateGutterWidth()
        let gutterWidth = gutterWidthConstraint?.constant ?? gutter.bounds.width
        let visibleWidth = max(scrollView.bounds.width, self.container.bounds.width - gutterWidth)
        let visibleHeight = max(scrollView.bounds.height, self.container.bounds.height)
        guard visibleWidth > 1, visibleHeight > 1 else { return }
        let wrap = wordWrap ?? container.widthTracksTextView
        let wasWrapped = container.lineBreakMode == .byCharWrapping
        let oldWidth = container.containerSize.width
        let repairing = textView.frame.width < 1 || textView.frame.height < 1
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: visibleWidth, height: visibleHeight)
        textView.maxSize = NSSize(
            width: wrap ? visibleWidth : CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        if textView.frame.width < visibleWidth { textView.frame.size.width = visibleWidth }
        if textView.frame.height < visibleHeight { textView.frame.size.height = visibleHeight }
        if repairing { textView.frame.origin = .zero }
        scrollView.tile()
        container.widthTracksTextView = wrap
        if document.buffer.storage.length >= Syntax.largeFileLimit {
            layoutLarge(
                wrap: wrap,
                visibleWidth: visibleWidth,
                visibleHeight: visibleHeight,
                container: container,
                layoutManager: layoutManager
            )
            return
        }
        layoutManager.allowsNonContiguousLayout = false
        let tall = CGFloat.greatestFiniteMagnitude
        if wrap {
            container.lineBreakMode = .byCharWrapping
            textView.frame.size.width = visibleWidth
            if textView.frame.height < visibleHeight {
                textView.frame.size.height = visibleHeight
            }
            container.containerSize = NSSize(width: visibleWidth, height: tall)
            if scrollView.hasHorizontalScroller { scrollView.hasHorizontalScroller = false }
        } else {
            let measure: CGFloat = 1_000_000
            container.lineBreakMode = .byClipping
            let length = (textView.string as NSString).length
            if wasWrapped || repairing {
                container.containerSize = NSSize(width: measure, height: tall)
                if length > 0 {
                    layoutManager.invalidateLayout(forCharacterRange: NSRange(location: 0, length: length), actualCharacterRange: nil)
                }
            }
            layoutManager.ensureLayout(for: container)
            func widestLine() -> CGFloat {
                var width: CGFloat = 0
                guard layoutManager.numberOfGlyphs > 0 else { return 0 }
                layoutManager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs)) { _, used, _, _, _ in
                    width = max(width, used.maxX)
                }
                return width
            }
            var usedWidth = widestLine()
            if usedWidth >= container.containerSize.width - 2, container.containerSize.width < measure - 1 {
                container.containerSize = NSSize(width: measure, height: tall)
                if length > 0 {
                    layoutManager.invalidateLayout(forCharacterRange: NSRange(location: 0, length: length), actualCharacterRange: nil)
                }
                layoutManager.ensureLayout(for: container)
                usedWidth = widestLine()
            }
            if !usedWidth.isFinite { usedWidth = 0 }
            let textWidth = max(visibleWidth, ceil(usedWidth + textView.textContainerOrigin.x + 8))
            container.containerSize = NSSize(width: textWidth, height: tall)
            textView.frame.size.width = textWidth
            if textView.frame.height < visibleHeight {
                textView.frame.size.height = visibleHeight
            }
            let needsHorizontal = textWidth > visibleWidth + 1
            if scrollView.hasHorizontalScroller != needsHorizontal {
                scrollView.hasHorizontalScroller = needsHorizontal
            }
        }
        if wasWrapped != wrap || repairing || abs(oldWidth - container.containerSize.width) > 0.5 {
            let length = (textView.string as NSString).length
            if length > 0 {
                layoutManager.invalidateLayout(forCharacterRange: NSRange(location: 0, length: length), actualCharacterRange: nil)
            }
            layoutManager.ensureLayout(for: container)
        }
        textView.needsDisplay = true
        gutter.needsDisplay = true
    }

    private func layoutLarge(wrap: Bool, visibleWidth: CGFloat, visibleHeight: CGFloat, container: NSTextContainer, layoutManager: NSLayoutManager) {
        layoutManager.allowsNonContiguousLayout = true
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: model.fontSize, weight: .regular)
        let step = max(layoutManager.defaultLineHeight(for: font), 1)
        let charWidth = max(("M" as NSString).size(withAttributes: [.font: font]).width, 1)
        if measuredGeneration != colorGeneration || measuredWrap != wrap || (wrap && abs(measuredWidth - visibleWidth) > 0.5) {
            let text = currentText()
            measuredColumns = longestLineLength(text)
            measuredLines = wrap
                ? wrappedLineCount(text, columns: max(1, Int(visibleWidth / charWidth)))
                : max(1, document.buffer.lineCount)
            measuredGeneration = colorGeneration
            measuredWrap = wrap
            measuredWidth = visibleWidth
        }
        let textWidth: CGFloat
        if wrap {
            if container.lineBreakMode != .byCharWrapping { container.lineBreakMode = .byCharWrapping }
            if !container.widthTracksTextView { container.widthTracksTextView = true }
            textWidth = visibleWidth
            if scrollView.hasHorizontalScroller { scrollView.hasHorizontalScroller = false }
        } else {
            if container.lineBreakMode != .byClipping { container.lineBreakMode = .byClipping }
            if container.widthTracksTextView { container.widthTracksTextView = false }
            let used = CGFloat(measuredColumns) * charWidth
            textWidth = max(visibleWidth, ceil(used + textView.textContainerOrigin.x + 16))
            let needsHorizontal = textWidth > visibleWidth + 1
            if scrollView.hasHorizontalScroller != needsHorizontal {
                scrollView.hasHorizontalScroller = needsHorizontal
            }
        }
        let contentHeight = max(
            visibleHeight,
            ceil(CGFloat(measuredLines) * step + textView.textContainerOrigin.y + textView.textContainerInset.height + 8)
        )
        if abs(container.containerSize.width - textWidth) > 0.5 || abs(container.containerSize.height - contentHeight) > 0.5 {
            container.containerSize = NSSize(width: textWidth, height: contentHeight)
        }
        if abs(textView.frame.width - textWidth) > 0.5 || abs(textView.frame.height - contentHeight) > 0.5 {
            textView.frame.size = NSSize(width: textWidth, height: contentHeight)
            gutter.needsDisplay = true
        }
    }

    private func currentText() -> NSString {
        if snapshotGeneration == colorGeneration { return snapshot }
        snapshot = document.buffer.storage.string as NSString
        snapshotGeneration = colorGeneration
        return snapshot
    }

    @objc func redrawRuler() {
        gutter.needsDisplay = true
        scheduleScrollSync()
    }

    func firstVisibleLine() -> Int {
        if document.buffer.storage.length >= Syntax.largeFileLimit,
           textView.textContainer?.widthTracksTextView != true {
            let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: model.fontSize, weight: .regular)
            let step = max(textView.layoutManager?.defaultLineHeight(for: font) ?? font.pointSize, 1)
            let y = max(0, scrollView.documentVisibleRect.minY - textView.textContainerOrigin.y)
            let line = Int(floor(y / step)) + 1
            return min(max(1, line), max(1, document.buffer.lineCount))
        }
        guard let layout = textView.layoutManager, let container = textView.textContainer, layout.numberOfGlyphs > 0 else { return 1 }
        let visible = scrollView.documentVisibleRect
        let point = NSPoint(x: 4, y: max(0, visible.minY - textView.textContainerOrigin.y + 2))
        var fraction: CGFloat = 0
        let glyph = layout.glyphIndex(for: point, in: container, fractionOfDistanceThroughGlyph: &fraction)
        let index = layout.characterIndexForGlyph(at: min(glyph, layout.numberOfGlyphs - 1))
        return document.buffer.position(at: index).line
    }

    func scrollToLine(_ line: Int) {
        guard !textView.hasMarkedText() else { return }
        suppressScrollSync = true
        if document.buffer.storage.length >= Syntax.largeFileLimit,
           textView.textContainer?.widthTracksTextView != true {
            let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: model.fontSize, weight: .regular)
            let step = max(textView.layoutManager?.defaultLineHeight(for: font) ?? font.pointSize, 1)
            let y = max(0, CGFloat(line - 1) * step)
            scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.minX, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            lastSyncedLine = line
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.suppressScrollSync = false
            }
            return
        }
        let range = document.buffer.rangeOfLine(line)
        if let layout = textView.layoutManager, let container = textView.textContainer {
            layout.ensureLayout(for: container)
            let glyph = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = layout.boundingRect(forGlyphRange: glyph, in: container)
            rect.origin.y += textView.textContainerOrigin.y
            let y = max(0, rect.minY - 8)
            scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.minX, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        lastSyncedLine = line
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.suppressScrollSync = false
        }
    }

    private func updateGutterWidth() {
        gutter.reportedLineCount = max(1, document.buffer.lineCount)
        let font = NSFont.monospacedDigitSystemFont(ofSize: model.fontSize, weight: .regular)
        let digits = max(3, String(max(1, document.buffer.lineCount)).count)
        let sample = String(repeating: "8", count: digits) as NSString
        let next = max(52, ceil(sample.size(withAttributes: [.font: font]).width) + 18)
        guard let constraint = gutterWidthConstraint, abs(constraint.constant - next) > 0.5 else { return }
        constraint.constant = next
    }

    private func scheduleScrollSync() {
        guard !suppressScrollSync else { return }
        scrollSyncWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.suppressScrollSync else { return }
            guard !self.textView.hasMarkedText() else { return }
            let line = self.firstVisibleLine()
            guard line != self.lastSyncedLine else { return }
            self.lastSyncedLine = line
            self.onVisibleLine?(line)
        }
        scrollSyncWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: work)
    }

    func textViewDidChange(_ notification: Notification) {
        gutter.needsDisplay = true
        updateGutterWidth()
        colorGeneration &+= 1
        guard !textView.hasMarkedText() else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.textView.hasMarkedText() else { return }
            self.updateWrapWidth()
            DispatchQueue.main.async { [weak self] in
                self?.paintColor()
            }
        }
    }

    private func paintColor() {
        guard !textView.hasMarkedText() else { return }
        let length = document.buffer.storage.length
        if length >= Syntax.largeFileLimit {
            textView.needsDisplay = true
            refreshBraces()
            return
        }
        Highlighter.apply(storage: document.buffer.storage, language: document.language)
        if length > 0 {
            textView.layoutManager?.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: length))
        }
        refreshBraces()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !textView.hasMarkedText() else { return }
        guard textView.window?.firstResponder === textView else { return }
        model.focus(group: group, documentID: document.id)
        model.updateCursor(textView)
        refreshBraces()
    }

    private func refreshBraces() {
        let manager = textView.layoutManager
        for range in braceSpans {
            manager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: range)
            manager?.invalidateDisplay(forCharacterRange: range)
        }
        braceSpans = []
        guard !textView.hasMarkedText() else { return }
        let selected = textView.selectedRange()
        guard selected.length == 0 else { return }
        let text = currentText()
        guard let pair = Syntax.bracePair(in: text, language: document.language, caret: selected.location) else { return }
        let color = NSColor.systemYellow.withAlphaComponent(model.theme == .dark ? 0.38 : 0.55)
        let ranges = [NSRange(location: pair.0, length: 1), NSRange(location: pair.1, length: 1)]
        for range in ranges where range.location >= 0 && NSMaxRange(range) <= text.length {
            manager?.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: range)
            manager?.invalidateDisplay(forCharacterRange: range)
        }
        braceSpans = ranges
    }
}
