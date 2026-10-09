import AppKit

final class LineNumberRulerView: NSRulerView {
    var bookmarkLines: Set<Int> = []
    var onToggle: ((Int) -> Void)?

    override var requiredThickness: CGFloat { 56 }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
        super.draw(dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = clientView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let relative = convert(NSZeroPoint, from: textView)
        let glyphRange = layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: textContainer)
        guard glyphRange.length > 0 || textView.string.isEmpty else { return }
        let string = textView.string as NSString
        let charStart = glyphRange.length == 0 ? 0 : layoutManager.characterIndexForGlyph(at: glyphRange.location)
        var line = 1 + newlineCount(string, upTo: charStart)
        var glyphIndex = glyphRange.location
        let limit = max(NSMaxRange(glyphRange), glyphIndex + 1)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        if string.length == 0 {
            drawLabel("1", y: textView.textContainerOrigin.y + relative.y, attributes: attributes, bookmarked: bookmarkLines.contains(1))
            return
        }

        while glyphIndex < limit && glyphIndex < layoutManager.numberOfGlyphs {
            var lineGlyphRange = NSRange()
            let fragment = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: &lineGlyphRange,
                withoutAdditionalLayout: true
            )
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            let lineCharRange = string.lineRange(for: NSRange(location: min(charIndex, max(string.length - 1, 0)), length: 0))
            if charIndex <= lineCharRange.location {
                let y = fragment.minY + textView.textContainerOrigin.y + relative.y
                drawLabel("\(line)", y: y, attributes: attributes, bookmarked: bookmarkLines.contains(line))
                line += 1
            }
            let next = NSMaxRange(lineGlyphRange)
            if next <= glyphIndex { break }
            glyphIndex = next
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let textView = clientView as? NSTextView else { return }
        let point = textView.convert(event.locationInWindow, from: nil)
        let index = textView.characterIndexForInsertion(at: point)
        let line = 1 + newlineCount(textView.string as NSString, upTo: index)
        onToggle?(line)
    }

    private func drawLabel(_ text: String, y: CGFloat, attributes: [NSAttributedString.Key: Any], bookmarked: Bool) {
        if bookmarked {
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: NSRect(x: 5, y: y + 4, width: 8, height: 8)).fill()
        }
        let label = text as NSString
        let size = label.size(withAttributes: attributes)
        label.draw(at: NSPoint(x: bounds.width - size.width - 8, y: y), withAttributes: attributes)
    }
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
