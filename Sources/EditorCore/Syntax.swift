import Foundation

public enum SyntaxKind: String, Sendable, Equatable {
    case keyword
    case type
    case value
    case number
    case string
    case comment
    case code
    case fence
    case heading
    case emphasis
    case strong
    case link
    case marker
    case function
    case namespace
    case key

    var skipsBrace: Bool {
        switch self {
        case .string, .comment, .code, .fence: return true
        default: return false
        }
    }
}

public struct SyntaxSpan: Sendable, Equatable {
    public var location: Int
    public var length: Int
    public var kind: SyntaxKind
}

public struct BracePair: Sendable, Equatable {
    public var open: String
    public var close: String

    public init(open: String, close: String) {
        self.open = open
        self.close = close
    }
}

public struct SyntaxRule: Sendable {
    public var keywords: Set<String>
    public var types: Set<String>
    public var values: Set<String>
    public var lineComment: String?
    public var blockCommentBegin: String?
    public var blockCommentEnd: String?
    public var stringQuotes: [String]
    public var braces: [BracePair]
    public var caseInsensitive: Bool
    public var markupTags: Bool
    public var hashPrefix: Bool
    public var atPrefix: Bool
    public var verbatimStrings: Bool
    /// 大写开头的名字按类型上色，例如类名、命名空间。
    public var pascalTypes: Bool
    /// 词里可以包含减号，例如 CSS 的 font-size。
    public var hyphenWords: Bool
    /// 冒号前面的字符串是键，例如 JSON。
    public var stringKeys: Bool

    public init(
        keywords: Set<String> = [],
        types: Set<String> = [],
        values: Set<String> = [],
        lineComment: String? = nil,
        blockCommentBegin: String? = nil,
        blockCommentEnd: String? = nil,
        stringQuotes: [String] = ["\""],
        braces: [BracePair] = [],
        caseInsensitive: Bool = false,
        markupTags: Bool = false,
        hashPrefix: Bool = false,
        atPrefix: Bool = false,
        verbatimStrings: Bool = false,
        pascalTypes: Bool = false,
        hyphenWords: Bool = false,
        stringKeys: Bool = false
    ) {
        self.keywords = keywords
        self.types = types
        self.values = values
        self.lineComment = lineComment
        self.blockCommentBegin = blockCommentBegin
        self.blockCommentEnd = blockCommentEnd
        self.stringQuotes = stringQuotes.sorted { ($0 as NSString).length > ($1 as NSString).length }
        self.braces = braces
        self.caseInsensitive = caseInsensitive
        self.markupTags = markupTags
        self.hashPrefix = hashPrefix
        self.atPrefix = atPrefix
        self.verbatimStrings = verbatimStrings
        self.pascalTypes = pascalTypes
        self.hyphenWords = hyphenWords
        self.stringKeys = stringKeys
    }
}

public enum Syntax {
    /// 超过这个长度就暂停上色和括号匹配，避免大文件卡住。
    public static let highlightLimit = 1_200_000
    /// 超过这个长度仍给看得见的文字上色，但不再把颜色写进整篇，也不再排版整篇。
    public static let largeFileLimit = 100_000
    private static var spanText: NSString?
    private static var spanLanguage: Language = .plaintext
    private static var spanCache: [SyntaxSpan] = []

    public static func rule(for language: Language) -> SyntaxRule {
        switch language {
        case .plaintext:
            return SyntaxRule(stringQuotes: [], braces: codeBraces)
        case .markdown:
            return SyntaxRule(stringQuotes: [], braces: codeBraces)
        case .json:
            return SyntaxRule(
                values: ["true", "false", "null"],
                stringQuotes: ["\""],
                braces: codeBraces,
                stringKeys: true
            )
        case .html:
            return SyntaxRule(
                blockCommentBegin: "<!--",
                blockCommentEnd: "-->",
                stringQuotes: ["\"", "'"],
                braces: codeBraces,
                markupTags: true
            )
        case .xml:
            return SyntaxRule(
                blockCommentBegin: "<!--",
                blockCommentEnd: "-->",
                stringQuotes: ["\"", "'"],
                braces: codeBraces,
                markupTags: true
            )
        case .css:
            return SyntaxRule(
                keywords: ["import", "media", "keyframes", "charset", "supports", "font-face", "namespace", "page", "layer", "container", "scope", "important", "display", "position", "top", "right", "bottom", "left", "z-index", "float", "clear", "width", "height", "min-width", "max-width", "min-height", "max-height", "margin", "padding", "border", "border-radius", "outline", "box-sizing", "box-shadow", "background", "background-color", "color", "opacity", "visibility", "overflow", "font", "font-size", "font-weight", "font-family", "line-height", "text-align", "text-decoration", "white-space", "flex", "flex-direction", "flex-wrap", "justify-content", "align-items", "align-content", "gap", "grid", "grid-template-columns", "grid-template-rows", "transform", "transition", "animation", "cursor", "content", "object-fit", "list-style", "vertical-align"],
                lineComment: "//",
                blockCommentBegin: "/*",
                blockCommentEnd: "*/",
                stringQuotes: ["\"", "'"],
                braces: codeBraces,
                atPrefix: true,
                hyphenWords: true
            )
        case .javascript:
            return SyntaxRule(
                keywords: ["break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do", "else", "export", "extends", "finally", "for", "from", "function", "if", "import", "in", "instanceof", "let", "new", "of", "return", "static", "super", "switch", "this", "throw", "try", "typeof", "var", "void", "while", "with", "yield", "async", "await", "as", "get", "set"],
                values: ["true", "false", "null", "undefined"],
                lineComment: "//",
                blockCommentBegin: "/*",
                blockCommentEnd: "*/",
                stringQuotes: ["`", "\"", "'"],
                braces: codeBraces,
                pascalTypes: true
            )
        case .typescript:
            return SyntaxRule(
                keywords: ["break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do", "else", "export", "extends", "finally", "for", "from", "function", "if", "import", "in", "instanceof", "let", "new", "of", "return", "static", "super", "switch", "this", "throw", "try", "typeof", "var", "while", "with", "yield", "async", "await", "as", "get", "set", "implements", "interface", "enum", "public", "private", "protected", "readonly", "satisfies", "type", "declare", "abstract", "namespace", "module", "keyof", "infer", "asserts", "override", "is"],
                types: ["string", "number", "boolean", "any", "void", "never", "unknown", "object", "bigint", "symbol", "undefined"],
                values: ["true", "false", "null", "undefined"],
                lineComment: "//",
                blockCommentBegin: "/*",
                blockCommentEnd: "*/",
                stringQuotes: ["`", "\"", "'"],
                braces: codeBraces,
                pascalTypes: true
            )
        case .python:
            return SyntaxRule(
                keywords: ["def", "class", "return", "if", "elif", "else", "for", "while", "import", "from", "as", "try", "except", "with", "lambda", "pass", "and", "or", "not", "in", "is", "yield", "raise", "finally", "global", "nonlocal", "assert", "del", "break", "continue", "async", "await", "match", "case"],
                values: ["None", "True", "False"],
                lineComment: "#",
                stringQuotes: ["\"\"\"", "'''", "\"", "'"],
                braces: codeBraces,
                pascalTypes: true
            )
        case .sql:
            return SyntaxRule(
                keywords: ["select", "from", "where", "insert", "update", "delete", "create", "alter", "drop", "table", "view", "index", "database", "schema", "and", "or", "not", "null", "join", "left", "right", "inner", "outer", "full", "cross", "on", "using", "group", "by", "order", "asc", "desc", "limit", "offset", "as", "into", "values", "set", "primary", "foreign", "key", "references", "constraint", "default", "check", "unique", "distinct", "having", "union", "all", "case", "when", "then", "else", "end", "begin", "declare", "between", "like", "exists", "in", "is", "cast", "count", "sum", "avg", "min", "max", "commit", "rollback", "transaction", "procedure", "function", "grant", "revoke"],
                lineComment: "--",
                blockCommentBegin: "/*",
                blockCommentEnd: "*/",
                stringQuotes: ["'", "\""],
                braces: codeBraces,
                caseInsensitive: true
            )
        case .shell:
            return SyntaxRule(
                keywords: ["if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac", "function", "return", "exit", "echo", "export", "local", "readonly", "declare", "typeset", "source", "alias", "unalias", "set", "unset", "shift", "trap", "eval", "exec", "cd", "test", "select", "in", "time"],
                lineComment: "#",
                stringQuotes: ["\"", "'"],
                braces: codeBraces
            )
        case .yaml:
            return SyntaxRule(
                values: ["true", "false", "null", "yes", "no", "on", "off"],
                lineComment: "#",
                stringQuotes: ["\"", "'"],
                braces: codeBraces
            )
        case .cpp:
            return SyntaxRule(
                keywords: ["alignas", "alignof", "and", "and_eq", "asm", "auto", "bitand", "bitor", "break", "case", "catch", "class", "compl", "concept", "const", "consteval", "constexpr", "constinit", "continue", "co_await", "co_return", "co_yield", "decltype", "default", "delete", "do", "else", "enum", "explicit", "export", "extern", "for", "friend", "goto", "if", "inline", "mutable", "namespace", "new", "noexcept", "not", "not_eq", "nullptr", "operator", "or", "or_eq", "private", "protected", "public", "register", "requires", "return", "sizeof", "static", "static_assert", "static_cast", "struct", "switch", "template", "this", "thread_local", "throw", "try", "typedef", "typeid", "typename", "union", "using", "virtual", "volatile", "while", "xor", "xor_eq", "override", "final", "module", "import", "#include", "#define", "#undef", "#if", "#ifdef", "#ifndef", "#endif", "#pragma", "#else", "#elif", "#error", "#warning"],
                types: ["void", "bool", "char", "char8_t", "char16_t", "char32_t", "wchar_t", "short", "int", "long", "float", "double", "signed", "unsigned", "size_t", "int8_t", "int16_t", "int32_t", "int64_t", "uint8_t", "uint16_t", "uint32_t", "uint64_t"],
                values: ["true", "false"],
                lineComment: "//",
                blockCommentBegin: "/*",
                blockCommentEnd: "*/",
                stringQuotes: ["\"", "'"],
                braces: codeBraces,
                hashPrefix: true,
                pascalTypes: true
            )
        case .csharp:
            return SyntaxRule(
                keywords: ["abstract", "as", "base", "break", "case", "catch", "checked", "class", "const", "continue", "default", "delegate", "do", "else", "enum", "event", "explicit", "extern", "finally", "fixed", "for", "foreach", "goto", "if", "implicit", "in", "interface", "internal", "is", "lock", "namespace", "new", "operator", "out", "override", "params", "private", "protected", "public", "readonly", "ref", "return", "sealed", "sizeof", "stackalloc", "static", "struct", "switch", "this", "throw", "try", "typeof", "unchecked", "unsafe", "using", "virtual", "volatile", "while", "async", "await", "var", "record", "nameof", "when", "yield", "get", "set", "init", "required", "file", "scoped", "#if", "#else", "#elif", "#endif", "#region", "#endregion", "#define", "#undef", "#pragma", "#nullable", "#line", "#error", "#warning"],
                types: ["bool", "byte", "char", "decimal", "double", "float", "int", "long", "object", "sbyte", "short", "string", "uint", "ulong", "ushort", "void"],
                values: ["true", "false", "null"],
                lineComment: "//",
                blockCommentBegin: "/*",
                blockCommentEnd: "*/",
                stringQuotes: ["\"", "'"],
                braces: codeBraces,
                hashPrefix: true,
                verbatimStrings: true,
                pascalTypes: true
            )
        case .java:
            return SyntaxRule(
                keywords: ["abstract", "assert", "break", "case", "catch", "class", "const", "continue", "default", "do", "else", "enum", "extends", "final", "finally", "for", "if", "implements", "import", "instanceof", "interface", "native", "new", "package", "private", "protected", "public", "return", "static", "strictfp", "super", "switch", "synchronized", "this", "throw", "throws", "transient", "try", "volatile", "while", "yield", "var", "record", "sealed", "permits", "module", "open", "opens", "requires", "exports", "provides", "uses", "to", "with", "transitive"],
                types: ["void", "boolean", "byte", "char", "short", "int", "long", "float", "double"],
                values: ["true", "false", "null"],
                lineComment: "//",
                blockCommentBegin: "/*",
                blockCommentEnd: "*/",
                stringQuotes: ["\"", "'"],
                braces: codeBraces,
                pascalTypes: true
            )
        }
    }

    public static func spans(in text: String, language: Language) -> [SyntaxSpan] {
        spans(in: text as NSString, language: language)
    }

    public static func spans(in text: NSString, language: Language) -> [SyntaxSpan] {
        if spanText === text, spanLanguage == language {
            return spanCache
        }
        let result = computeSpans(in: text, language: language)
        spanText = text
        spanLanguage = language
        spanCache = result
        return result
    }

    private static func computeSpans(in text: NSString, language: Language) -> [SyntaxSpan] {
        guard text.length > 0, text.length < highlightLimit, language != .plaintext else { return [] }
        if language == .markdown {
            return markdownSpans(text)
        }
        if language == .yaml {
            var spans: [SyntaxSpan] = []
            scanYaml(text, spans: &spans)
            return spans
        }
        var spans: [SyntaxSpan] = []
        scanCode(text, rule: rule(for: language), spans: &spans)
        return spans
    }

    /// 光标紧挨着的括号，和它配上的另一个括号。字符串和注释里的括号不算。
    public static func bracePair(in text: String, language: Language, caret: Int) -> (Int, Int)? {
        bracePair(in: text as NSString, language: language, caret: caret)
    }

    public static func bracePair(in text: NSString, language: Language, caret: Int) -> (Int, Int)? {
        let pairs = rule(for: language).braces
        guard !pairs.isEmpty, text.length > 0, text.length < highlightLimit, caret >= 0, caret <= text.length else { return nil }
        guard let anchor = anchorBrace(text, caret: caret, pairs: pairs) else { return nil }
        let covered = skipRanges(spans(in: text, language: language))
        if covers(anchor.index, covered) { return nil }
        return seek(text, anchor: anchor, covered: covered)
    }
}

private let codeBraces = [
    BracePair(open: "{", close: "}"),
    BracePair(open: "(", close: ")"),
    BracePair(open: "[", close: "]")
]

private struct BraceAnchor {
    var index: Int
    var open: unichar
    var close: unichar
    var forward: Bool
}

private enum Expect {
    case type
    case function
    case namespace
}

private let typeIntroducers: Set<String> = ["class", "struct", "interface", "enum", "record", "protocol", "extension", "typealias", "trait", "impl", "type", "new"]
private let functionIntroducers: Set<String> = ["func", "function", "def", "fn", "sub"]

private struct Carry {
    var blockEnd: String?
    var stringEnd: String?
    var verbatim = false
    var expect: Expect?
}

private func scanCode(_ text: NSString, rule: SyntaxRule, spans: inout [SyntaxSpan]) {
    var index = 0
    var carry = Carry()
    while index < text.length {
        let lineRange = text.lineRange(for: NSRange(location: index, length: 0))
        let line = text.substring(with: lineRange) as NSString
        scanCodeLine(line, base: lineRange.location, text: text, rule: rule, carry: &carry, spans: &spans)
        let next = NSMaxRange(lineRange)
        if next <= index { break }
        index = next
    }
}

private func scanCodeLine(_ line: NSString, base: Int, text: NSString, rule: SyntaxRule, carry: inout Carry, spans: inout [SyntaxSpan]) {
    var cursor = 0
    if let endMark = carry.blockEnd {
        if let end = findMark(line, from: 0, mark: endMark, escape: false, verbatim: false) {
            emit(base, 0, end, .comment, &spans)
            carry.blockEnd = nil
            cursor = end
        } else {
            emit(base, 0, line.length, .comment, &spans)
            return
        }
    } else if let endMark = carry.stringEnd {
        if let end = findMark(line, from: 0, mark: endMark, escape: !carry.verbatim, verbatim: carry.verbatim) {
            emitString(base, 0, end, text, rule, &spans)
            carry.stringEnd = nil
            carry.verbatim = false
            cursor = end
        } else {
            emit(base, 0, line.length, .string, &spans)
            return
        }
    }

    while cursor < line.length {
        let character = line.character(at: cursor)
        if character == 10 || character == 13 { break }

        if let lineComment = rule.lineComment, hasPrefix(line, cursor, lineComment) {
            emit(base, cursor, line.length, .comment, &spans)
            return
        }
        if let begin = rule.blockCommentBegin, let endMark = rule.blockCommentEnd, hasPrefix(line, cursor, begin) {
            let content = cursor + (begin as NSString).length
            if let end = findMark(line, from: content, mark: endMark, escape: false, verbatim: false) {
                emit(base, cursor, end, .comment, &spans)
                cursor = end
                continue
            }
            emit(base, cursor, line.length, .comment, &spans)
            carry.blockEnd = endMark
            return
        }
        if rule.verbatimStrings, character == 64, cursor + 1 < line.length, line.character(at: cursor + 1) == 34 {
            let content = cursor + 2
            if let end = findMark(line, from: content, mark: "\"", escape: false, verbatim: true) {
                emitString(base, cursor, end, text, rule, &spans)
                cursor = end
                continue
            }
            emit(base, cursor, line.length, .string, &spans)
            carry.stringEnd = "\""
            carry.verbatim = true
            return
        }
        if let quote = matchingQuote(line, cursor, rule.stringQuotes) {
            let mark = quote as NSString
            let content = cursor + mark.length
            let multiline = mark.length >= 3 || quote == "`"
            if let end = findMark(line, from: content, mark: quote, escape: true, verbatim: false) {
                emitString(base, cursor, end, text, rule, &spans)
                cursor = end
                continue
            }
            emit(base, cursor, line.length, .string, &spans)
            if multiline {
                carry.stringEnd = quote
            }
            return
        }
        if character >= 48 && character <= 57 {
            var end = cursor + 1
            while end < line.length {
                let next = line.character(at: end)
                if (next >= 48 && next <= 57) || next == 46 { end += 1 } else { break }
            }
            emit(base, cursor, end, .number, &spans)
            cursor = end
            continue
        }
        if isWordStart(character, rule: rule) {
            let startedWithAt = character == 64
            var end = cursor + 1
            while end < line.length {
                let next = line.character(at: end)
                if isWordContinue(next) || ((rule.hyphenWords || startedWithAt) && next == 45) { end += 1 } else { break }
            }
            let word = line.substring(with: NSRange(location: cursor, length: end - cursor))
            let folded = rule.caseInsensitive ? word.lowercased() : word
            let lookup = folded.first == "@" || folded.first == "#" ? String(folded.dropFirst()) : folded
            if rule.keywords.contains(folded) || rule.keywords.contains(lookup) {
                emit(base, cursor, end, .keyword, &spans)
                if lookup == "namespace" || lookup == "using" {
                    carry.expect = .namespace
                } else if lookup == "static", carry.expect == .namespace {
                    // using static 后面仍按命名空间接着涂
                } else if typeIntroducers.contains(lookup) {
                    carry.expect = .type
                } else if functionIntroducers.contains(lookup) {
                    carry.expect = .function
                } else {
                    carry.expect = nil
                }
            } else if rule.types.contains(folded) || rule.types.contains(lookup) {
                emit(base, cursor, end, .type, &spans)
                carry.expect = nil
            } else if rule.values.contains(folded) || rule.values.contains(lookup) {
                emit(base, cursor, end, .value, &spans)
                carry.expect = nil
            } else if rule.markupTags, cursor > 0 {
                let previous = line.character(at: cursor - 1)
                if previous == 60 || previous == 47 {
                    emit(base, cursor, end, .keyword, &spans)
                }
                carry.expect = nil
            } else if let kind = identifierKind(line, word: word, from: end, rule: rule, expect: carry.expect) {
                emit(base, cursor, end, kind, &spans)
                if kind != .namespace { carry.expect = nil }
            }
            cursor = end
            continue
        }
        if character == 32 || character == 9 || character == 10 || character == 13 {
            cursor += 1
            continue
        }
        if character == 46, carry.expect == .namespace {
            cursor += 1
            continue
        }
        if character == 58, cursor + 1 >= line.length || line.character(at: cursor + 1) != 58 {
            carry.expect = .type
            cursor += 1
            continue
        }
        carry.expect = nil
        cursor += 1
    }
}

private func identifierKind(_ line: NSString, word: String, from: Int, rule: SyntaxRule, expect: Expect?) -> SyntaxKind? {
    if expect == .namespace { return .namespace }
    if expect == .type { return .type }
    if expect == .function { return .function }
    let next = nextSignificant(line, from)
    if next < line.length, line.character(at: next) == 40 { return .function }
    if rule.pascalTypes, word.unicodeScalars.first.map({ CharacterSet.uppercaseLetters.contains($0) }) == true {
        return .type
    }
    return nil
}

private func nextSignificant(_ line: NSString, _ index: Int) -> Int {
    var index = index
    while index < line.length {
        let character = line.character(at: index)
        if character != 32 && character != 9 { return index }
        index += 1
    }
    return index
}

private func isWordStart(_ character: unichar, rule: SyntaxRule) -> Bool {
    if character == 95 || (character >= 65 && character <= 90) || (character >= 97 && character <= 122) { return true }
    if character > 127 { return true }
    if rule.hashPrefix, character == 35 { return true }
    if rule.atPrefix, character == 64 { return true }
    return false
}

private func isWordContinue(_ character: unichar) -> Bool {
    if character == 95 || (character >= 48 && character <= 57) { return true }
    if (character >= 65 && character <= 90) || (character >= 97 && character <= 122) { return true }
    return character > 127
}

private func matchingQuote(_ line: NSString, _ index: Int, _ quotes: [String]) -> String? {
    for quote in quotes where hasPrefix(line, index, quote) {
        return quote
    }
    return nil
}

private func hasPrefix(_ line: NSString, _ index: Int, _ prefix: String) -> Bool {
    let mark = prefix as NSString
    guard index >= 0, index + mark.length <= line.length else { return false }
    return line.substring(with: NSRange(location: index, length: mark.length)) == prefix
}

private func findMark(_ line: NSString, from: Int, mark: String, escape: Bool, verbatim: Bool) -> Int? {
    let needle = mark as NSString
    var index = from
    while index < line.length {
        let character = line.character(at: index)
        if character == 10 || character == 13 { return nil }
        if verbatim, needle.length == 1, needle.character(at: 0) == 34, character == 34 {
            if index + 1 < line.length, line.character(at: index + 1) == 34 {
                index += 2
                continue
            }
            return index + 1
        }
        if escape, character == 92 {
            index += 2
            continue
        }
        if hasPrefix(line, index, mark) {
            return index + needle.length
        }
        index += 1
    }
    return nil
}

private func emitString(_ base: Int, _ start: Int, _ end: Int, _ text: NSString, _ rule: SyntaxRule, _ spans: inout [SyntaxSpan]) {
    let kind: SyntaxKind = rule.stringKeys && colonFollows(text, base + end) ? .key : .string
    emit(base, start, end, kind, &spans)
}

private func colonFollows(_ text: NSString, _ index: Int) -> Bool {
    var index = index
    while index < text.length {
        let character = text.character(at: index)
        if character == 32 || character == 9 || character == 10 || character == 13 {
            index += 1
            continue
        }
        return character == 58
    }
    return false
}

private func emit(_ base: Int, _ start: Int, _ end: Int, _ kind: SyntaxKind, _ spans: inout [SyntaxSpan]) {
    guard end > start else { return }
    spans.append(SyntaxSpan(location: base + start, length: end - start, kind: kind))
}

private func anchorBrace(_ text: NSString, caret: Int, pairs: [BracePair]) -> BraceAnchor? {
    if caret > 0, let anchor = braceAnchor(text, index: caret - 1, pairs: pairs) {
        return anchor
    }
    if caret < text.length, let anchor = braceAnchor(text, index: caret, pairs: pairs) {
        return anchor
    }
    return nil
}

private func braceAnchor(_ text: NSString, index: Int, pairs: [BracePair]) -> BraceAnchor? {
    let character = text.character(at: index)
    for pair in pairs {
        let open = (pair.open as NSString).character(at: 0)
        let close = (pair.close as NSString).character(at: 0)
        if character == open {
            return BraceAnchor(index: index, open: open, close: close, forward: true)
        }
        if character == close {
            return BraceAnchor(index: index, open: open, close: close, forward: false)
        }
    }
    return nil
}

private func skipRanges(_ spans: [SyntaxSpan]) -> [Range<Int>] {
    spans.compactMap { span in
        guard span.kind.skipsBrace, span.length > 0 else { return nil }
        return span.location..<(span.location + span.length)
    }.sorted { $0.lowerBound < $1.lowerBound }
}

private func covers(_ index: Int, _ ranges: [Range<Int>]) -> Bool {
    var low = 0
    var high = ranges.count
    while low < high {
        let mid = (low + high) / 2
        if ranges[mid].upperBound <= index { low = mid + 1 } else { high = mid }
    }
    if low > 0, ranges[low - 1].contains(index) { return true }
    if low < ranges.count, ranges[low].contains(index) { return true }
    return false
}

private func coveringRange(_ index: Int, _ ranges: [Range<Int>]) -> Range<Int>? {
    var low = 0
    var high = ranges.count
    while low < high {
        let mid = (low + high) / 2
        if ranges[mid].upperBound <= index { low = mid + 1 } else { high = mid }
    }
    if low < ranges.count, ranges[low].contains(index) { return ranges[low] }
    if low > 0, ranges[low - 1].contains(index) { return ranges[low - 1] }
    return nil
}

private func jumpForward(_ index: Int, _ ranges: [Range<Int>]) -> Int {
    guard let range = coveringRange(index, ranges) else { return index }
    return range.upperBound
}

private func jumpBackward(_ index: Int, _ ranges: [Range<Int>]) -> Int {
    guard let range = coveringRange(index, ranges) else { return index }
    return range.lowerBound - 1
}

private func seek(_ text: NSString, anchor: BraceAnchor, covered: [Range<Int>]) -> (Int, Int)? {
    var depth = 0
    if anchor.forward {
        var index = anchor.index + 1
        while index < text.length {
            let jumped = jumpForward(index, covered)
        if jumped != index {
            index = jumped
            continue
        }
        let character = text.character(at: index)
        if character == anchor.open {
            depth += 1
        } else if character == anchor.close {
            if depth == 0 { return (anchor.index, index) }
            depth -= 1
        }
        index += 1
    }
    return nil
    }
    var index = anchor.index - 1
    while index >= 0 {
        let jumped = jumpBackward(index, covered)
        if jumped != index {
            index = jumped
            continue
        }
        let character = text.character(at: index)
        if character == anchor.close {
            depth += 1
        } else if character == anchor.open {
            if depth == 0 { return (anchor.index, index) }
            depth -= 1
        }
        index -= 1
    }
    return nil
}

private func scanYaml(_ text: NSString, spans: inout [SyntaxSpan]) {
    var index = 0
    while index < text.length {
        let lineRange = text.lineRange(for: NSRange(location: index, length: 0))
        let line = text.substring(with: lineRange) as NSString
        scanYamlLine(line, base: lineRange.location, spans: &spans)
        let next = NSMaxRange(lineRange)
        if next <= index { break }
        index = next
    }
}

private func scanYamlLine(_ line: NSString, base: Int, spans: inout [SyntaxSpan]) {
    var cursor = yamlSkipSpace(line, 0)
    if yamlAtLineEnd(line, cursor) { return }
    if line.character(at: cursor) == 35 {
        emit(base, cursor, yamlLineEnd(line), .comment, &spans)
        return
    }
    if yamlIsMarker(line, cursor) {
        emit(base, cursor, cursor + 3, .marker, &spans)
        return
    }
    if line.character(at: cursor) == 45, yamlDashIsList(line, cursor) {
        cursor = yamlSkipSpace(line, cursor + 1)
        if yamlAtLineEnd(line, cursor) { return }
        if line.character(at: cursor) == 35 {
            emit(base, cursor, yamlLineEnd(line), .comment, &spans)
            return
        }
    }
    let starter = line.character(at: cursor)
    if starter != 123, starter != 91, let found = yamlKey(line, cursor) {
        emit(base, found.keyStart, found.keyEnd, .key, &spans)
        cursor = yamlSkipSpace(line, found.colon + 1)
        if yamlAtLineEnd(line, cursor) { return }
        if line.character(at: cursor) == 35 {
            emit(base, cursor, yamlLineEnd(line), .comment, &spans)
            return
        }
    }
    scanYamlScalar(line, base: base, from: cursor, spans: &spans)
}

private func scanYamlScalar(_ line: NSString, base: Int, from: Int, spans: inout [SyntaxSpan]) {
    let quote = line.character(at: from)
    if quote == 34 || quote == 39 {
        if let end = yamlQuotedEnd(line, from) {
            emit(base, from, end, .string, &spans)
            let after = yamlSkipSpace(line, end)
            if after < line.length, line.character(at: after) == 35 {
                emit(base, after, yamlLineEnd(line), .comment, &spans)
            }
            return
        }
        emit(base, from, yamlLineEnd(line), .string, &spans)
        return
    }
    var end = from
    while end < line.length {
        let character = line.character(at: end)
        if character == 10 || character == 13 { break }
        if character == 35, end > from, yamlIsSpace(line.character(at: end - 1)) { break }
        end += 1
    }
    var trim = end
    while trim > from, yamlIsSpace(line.character(at: trim - 1)) { trim -= 1 }
    if trim > from {
        let text = line.substring(with: NSRange(location: from, length: trim - from))
        let kind: SyntaxKind = isYamlBool(text) ? .value : (isYamlNumber(text) ? .number : .string)
        emit(base, from, trim, kind, &spans)
    }
    if end < line.length, line.character(at: end) == 35 {
        emit(base, end, yamlLineEnd(line), .comment, &spans)
    }
}

private func yamlKey(_ line: NSString, _ start: Int) -> (keyStart: Int, keyEnd: Int, colon: Int)? {
    let character = line.character(at: start)
    if character == 34 || character == 39 {
        guard let end = yamlQuotedEnd(line, start) else { return nil }
        let colon = yamlSkipSpace(line, end)
        guard yamlColonSeparates(line, colon) else { return nil }
        return (start, end, colon)
    }
    var index = start
    while index < line.length {
        let character = line.character(at: index)
        if character == 10 || character == 13 { return nil }
        if character == 35, index > start, yamlIsSpace(line.character(at: index - 1)) { return nil }
        if yamlColonSeparates(line, index) {
            var keyEnd = index
            while keyEnd > start, yamlIsSpace(line.character(at: keyEnd - 1)) { keyEnd -= 1 }
            guard keyEnd > start else { return nil }
            return (start, keyEnd, index)
        }
        index += 1
    }
    return nil
}

private func yamlQuotedEnd(_ line: NSString, _ start: Int) -> Int? {
    let quote = line.character(at: start)
    var index = start + 1
    while index < line.length {
        let character = line.character(at: index)
        if character == 10 || character == 13 { return nil }
        if quote == 39, character == 39 {
            if index + 1 < line.length, line.character(at: index + 1) == 39 {
                index += 2
                continue
            }
            return index + 1
        }
        if quote == 34 {
            if character == 92 {
                index += 2
                continue
            }
            if character == 34 { return index + 1 }
        }
        index += 1
    }
    return nil
}

private func yamlColonSeparates(_ line: NSString, _ index: Int) -> Bool {
    guard index < line.length, line.character(at: index) == 58 else { return false }
    let next = index + 1
    if next >= line.length { return true }
    let character = line.character(at: next)
    return character == 32 || character == 9 || character == 10 || character == 13 || character == 35
}

private func yamlDashIsList(_ line: NSString, _ index: Int) -> Bool {
    let next = index + 1
    if next >= line.length { return true }
    let character = line.character(at: next)
    return character == 32 || character == 9 || character == 10 || character == 13
}

private func yamlIsMarker(_ line: NSString, _ index: Int) -> Bool {
    guard index + 3 <= line.length else { return false }
    let mark = line.substring(with: NSRange(location: index, length: 3))
    guard mark == "---" || mark == "..." else { return false }
    let next = index + 3
    if next >= line.length { return true }
    let character = line.character(at: next)
    return character == 32 || character == 9 || character == 10 || character == 13 || character == 35
}

private func yamlSkipSpace(_ line: NSString, _ index: Int) -> Int {
    var index = index
    while index < line.length, yamlIsSpace(line.character(at: index)) { index += 1 }
    return index
}

private func yamlAtLineEnd(_ line: NSString, _ index: Int) -> Bool {
    if index >= line.length { return true }
    let character = line.character(at: index)
    return character == 10 || character == 13
}

private func yamlLineEnd(_ line: NSString) -> Int {
    var index = 0
    while index < line.length {
        let character = line.character(at: index)
        if character == 10 || character == 13 { return index }
        index += 1
    }
    return line.length
}

private func yamlIsSpace(_ character: unichar) -> Bool {
    character == 32 || character == 9
}

private func isYamlBool(_ text: String) -> Bool {
    ["true", "false", "yes", "no", "on", "off", "null", "~"].contains(text.lowercased())
}

private func isYamlNumber(_ text: String) -> Bool {
    var index = text.startIndex
    guard index < text.endIndex else { return false }
    if text[index] == "+" || text[index] == "-" {
        index = text.index(after: index)
        guard index < text.endIndex else { return false }
    }
    var sawDigit = false
    var sawDot = false
    while index < text.endIndex {
        let character = text[index]
        if character >= "0", character <= "9" {
            sawDigit = true
        } else if character == ".", !sawDot {
            sawDot = true
        } else if character == "e" || character == "E" {
            guard sawDigit else { return false }
            index = text.index(after: index)
            if index < text.endIndex, text[index] == "+" || text[index] == "-" {
                index = text.index(after: index)
            }
            var exponent = false
            while index < text.endIndex, text[index] >= "0", text[index] <= "9" {
                exponent = true
                index = text.index(after: index)
            }
            return exponent && index == text.endIndex
        } else {
            return false
        }
        index = text.index(after: index)
    }
    return sawDigit
}

private let markdownItalic = try! NSRegularExpression(pattern: #"\*[^*\n]+\*|_[^_\n]+_"#)
private let markdownBold = try! NSRegularExpression(pattern: #"\*\*[^*\n]+\*\*|__[^_\n]+__"#)
private let markdownLink = try! NSRegularExpression(pattern: #"!\[[^\]\n]*\]\([^)\n]+\)|\[[^\]\n]+\]\([^)\n]+\)"#)
private let markdownCode = try! NSRegularExpression(pattern: #"`[^`\n]+`"#)
private let markdownList = try! NSRegularExpression(pattern: #"^[ \t]*([-*+]|\d+\.) "#)

private func markdownSpans(_ text: NSString) -> [SyntaxSpan] {
    var spans: [SyntaxSpan] = []
    var index = 0
    var fence = false
    while index < text.length {
        let lineRange = text.lineRange(for: NSRange(location: index, length: 0))
        let line = text.substring(with: lineRange)
        colorMarkdown(line: line, lineRange: lineRange, fence: &fence, spans: &spans)
        let next = NSMaxRange(lineRange)
        if next <= index { break }
        index = next
    }
    return spans
}

private func colorMarkdown(line: String, lineRange: NSRange, fence: inout Bool, spans: inout [SyntaxSpan]) {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
        fence.toggle()
        spans.append(SyntaxSpan(location: lineRange.location, length: lineRange.length, kind: .fence))
        return
    }
    if fence {
        spans.append(SyntaxSpan(location: lineRange.location, length: lineRange.length, kind: .fence))
        return
    }
    if markdownHeading(trimmed) {
        spans.append(SyntaxSpan(location: lineRange.location, length: lineRange.length, kind: .heading))
        return
    }
    if trimmed.hasPrefix(">") {
        spans.append(SyntaxSpan(location: lineRange.location, length: lineRange.length, kind: .marker))
        return
    }
    let ns = line as NSString
    addMarkdown(markdownList, .marker, ns, lineRange, &spans)
    addMarkdown(markdownItalic, .emphasis, ns, lineRange, &spans)
    addMarkdown(markdownBold, .strong, ns, lineRange, &spans)
    addMarkdown(markdownLink, .link, ns, lineRange, &spans)
    addMarkdown(markdownCode, .code, ns, lineRange, &spans)
}

private func markdownHeading(_ trimmed: String) -> Bool {
    var level = 0
    for character in trimmed {
        if character == "#" { level += 1 } else { break }
    }
    guard (1...6).contains(level) else { return false }
    let rest = trimmed.dropFirst(level)
    return rest.isEmpty || rest.first == " "
}

private func addMarkdown(_ expression: NSRegularExpression, _ kind: SyntaxKind, _ line: NSString, _ lineRange: NSRange, _ spans: inout [SyntaxSpan]) {
    let range = NSRange(location: 0, length: line.length)
    for match in expression.matches(in: line as String, range: range) {
        let found = match.range
        guard found.location != NSNotFound, found.length > 0 else { continue }
        spans.append(SyntaxSpan(location: lineRange.location + found.location, length: found.length, kind: kind))
    }
}
