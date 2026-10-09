import AppKit
import EditorCore

enum Highlighter {
    private static var cachedGeneration = -1
    private static var cachedLanguage: Language = .plaintext
    private static var cachedText: NSString?
    private static var cachedTokens: [Token] = []

    static func apply(storage: NSTextStorage, language: Language) {
        if storage.length >= Syntax.largeFileLimit {
            for manager in storage.layoutManagers {
                manager.firstTextView?.needsDisplay = true
            }
            return
        }
        let full = NSRange(location: 0, length: storage.length)
        for manager in storage.layoutManagers {
            manager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
        }
        guard storage.length > 0, storage.length < Syntax.highlightLimit, language != .plaintext else { return }
        let tokens = tokens(for: storage.string as NSString, language: language, generation: cachedGeneration)
        for token in tokens {
            for manager in storage.layoutManagers {
                manager.addTemporaryAttribute(.foregroundColor, value: token.color, forCharacterRange: token.range)
            }
        }
    }

    /// 绘制时按当前文本取色。刚插入的字符上，布局管理器会清掉临时颜色，所以这里在画的时候再给一次。
    static func drawingColor(text: NSString, language: Language, generation: Int, at index: Int, effectiveRange: NSRangePointer?) -> NSColor? {
        let tokens = tokens(for: text, language: language, generation: generation)
        return lookup(tokens, textLength: text.length, index: index, effectiveRange: effectiveRange)
    }

    private static func tokens(for text: NSString, language: Language, generation: Int) -> [Token] {
        if cachedGeneration == generation, cachedLanguage == language, cachedText === text {
            return cachedTokens
        }
        let tokens = (text.length > 0 && text.length < Syntax.highlightLimit && language != .plaintext)
            ? tokenize(text, language: language)
            : []
        cachedGeneration = generation
        cachedLanguage = language
        cachedText = text
        cachedTokens = tokens
        return tokens
    }
}

private struct Token {
    var range: NSRange
    var color: NSColor
}

private func lookup(_ tokens: [Token], textLength: Int, index: Int, effectiveRange: NSRangePointer?) -> NSColor? {
    guard index >= 0, index < textLength else {
        effectiveRange?.pointee = NSRange(location: max(0, index), length: 0)
        return nil
    }
    if tokens.count >= 4_000 {
        return lookupFast(tokens, textLength: textLength, index: index, effectiveRange: effectiveRange)
    }
    var winnerIndex: Int?
    for (offset, token) in tokens.enumerated() {
        let start = token.range.location
        let end = start + token.range.length
        if index >= start, index < end {
            winnerIndex = offset
        }
    }
    if let winnerIndex {
        let winner = tokens[winnerIndex]
        var start = winner.range.location
        var end = winner.range.location + winner.range.length
        if winnerIndex + 1 < tokens.count {
            for token in tokens[(winnerIndex + 1)...] {
                let tokenStart = token.range.location
                let tokenEnd = tokenStart + token.range.length
                if tokenStart > index, tokenStart < end {
                    end = tokenStart
                }
                if tokenEnd <= index, tokenEnd > start {
                    start = tokenEnd
                }
            }
        }
        effectiveRange?.pointee = NSRange(location: start, length: max(1, end - start))
        return winner.color
    }
    var next = textLength
    for token in tokens where token.range.location > index {
        next = min(next, token.range.location)
    }
    effectiveRange?.pointee = NSRange(location: index, length: max(1, next - index))
    return nil
}

private func lookupFast(_ tokens: [Token], textLength: Int, index: Int, effectiveRange: NSRangePointer?) -> NSColor? {
    var low = 0
    var high = tokens.count
    while low < high {
        let mid = (low + high) / 2
        if tokens[mid].range.location <= index { low = mid + 1 } else { high = mid }
    }
    var cursor = low - 1
    while cursor >= 0 {
        let token = tokens[cursor]
        let start = token.range.location
        let end = start + token.range.length
        if index >= start, index < end {
            effectiveRange?.pointee = NSRange(location: start, length: max(1, end - start))
            return token.color
        }
        if cursor == 0 || tokens[cursor - 1].range.location + tokens[cursor - 1].range.length <= start {
            break
        }
        cursor -= 1
    }
    let next = low < tokens.count ? tokens[low].range.location : textLength
    effectiveRange?.pointee = NSRange(location: index, length: max(1, next - index))
    return nil
}

private func tokenize(_ text: NSString, language: Language) -> [Token] {
    Syntax.spans(in: text, language: language).map { span in
        Token(range: NSRange(location: span.location, length: span.length), color: color(for: span.kind))
    }
}

private func color(for kind: SyntaxKind) -> NSColor {
    switch kind {
    case .keyword, .heading, .namespace, .key: return .systemBlue
    case .type, .link: return .systemTeal
    case .value, .strong: return .systemPink
    case .number, .emphasis: return .systemPurple
    case .string, .code: return .systemOrange
    case .comment, .marker: return .secondaryLabelColor
    case .fence: return .systemGreen
    case .function: return .systemBrown
    }
}

