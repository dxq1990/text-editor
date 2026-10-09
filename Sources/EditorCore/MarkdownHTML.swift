import Foundation

public enum MarkdownHTML {
    public static func render(_ source: String) -> String {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return renderLines(lines, annotate: true)
    }

    private static func renderLines(_ lines: [String], annotate: Bool) -> String {
        var index = 0
        var parts: [String] = []
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
                continue
            }
            if isFence(line) {
                let start = index + 1
                let marker = fenceMarker(line)
                let lang = fenceLanguage(line)
                index += 1
                var body: [String] = []
                while index < lines.count && !closesFence(lines[index], marker: marker) {
                    body.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                let klass = lang.isEmpty ? "" : " class=\"language-\(escapeAttr(lang))\""
                parts.append("\(openTag("pre", line: start, annotate: annotate))<code\(klass)>\(escape(body.joined(separator: "\n")))</code></pre>")
                continue
            }
            if isThematicBreak(line) {
                let start = index + 1
                parts.append(annotate ? "<hr data-line=\"\(start)\">" : "<hr>")
                index += 1
                continue
            }
            if let level = headingLevel(line) {
                let start = index + 1
                parts.append("\(openTag("h\(level)", line: start, annotate: annotate))\(renderInline(headingText(line)))</h\(level)>")
                index += 1
                continue
            }
            if line.hasPrefix(">") {
                let start = index + 1
                var quoted: [String] = []
                while index < lines.count, lines[index].hasPrefix(">") {
                    var item = String(lines[index].dropFirst())
                    if item.hasPrefix(" ") { item.removeFirst() }
                    quoted.append(item)
                    index += 1
                }
                parts.append("\(openTag("blockquote", line: start, annotate: annotate))\(renderLines(quoted, annotate: false))</blockquote>")
                continue
            }
            if isTableStart(lines, index) {
                let start = index + 1
                let header = splitRow(lines[index])
                index += 2
                var rows: [[String]] = []
                while index < lines.count, looksLikeRow(lines[index]) {
                    rows.append(splitRow(lines[index]))
                    index += 1
                }
                let table = renderTable(header: header, rows: rows)
                if annotate {
                    parts.append(table.replacingOccurrences(of: "<table>", with: "<table data-line=\"\(start)\">"))
                } else {
                    parts.append(table)
                }
                continue
            }
            if isUnordered(line) {
                parts.append(renderList(lines, index: &index, ordered: false, annotate: annotate))
                continue
            }
            if isOrdered(line) {
                parts.append(renderList(lines, index: &index, ordered: true, annotate: annotate))
                continue
            }

            let start = index + 1
            var paragraph: [String] = []
            while index < lines.count {
                let current = lines[index]
                if current.trimmingCharacters(in: .whitespaces).isEmpty || isBlockStart(lines, index) { break }
                paragraph.append(current)
                index += 1
            }
            if !paragraph.isEmpty {
                parts.append("\(openTag("p", line: start, annotate: annotate))\(renderParagraph(paragraph))</p>")
            }
        }
        return parts.joined(separator: "\n")
    }

    public static func renderInline(_ raw: String) -> String {
        var result = ""
        var rest = Substring(raw)
        while let start = rest.firstIndex(of: "`") {
            result += formatPlain(String(rest[..<start]))
            let after = rest.index(after: start)
            if let end = rest[after...].firstIndex(of: "`") {
                result += "<code>" + escape(String(rest[after..<end])) + "</code>"
                rest = rest[rest.index(after: end)...]
            } else {
                result += formatPlain(String(rest[start...]))
                rest = ""
                break
            }
        }
        result += formatPlain(String(rest))
        return result
    }
}

private func openTag(_ tag: String, line: Int, annotate: Bool) -> String {
    annotate ? "<\(tag) data-line=\"\(line)\">" : "<\(tag)>"
}

private func renderList(_ lines: [String], index: inout Int, ordered: Bool, annotate: Bool) -> String {
    var items: [String] = []
    let matches: (String) -> Bool = ordered ? isOrdered : isUnordered
    while index < lines.count, matches(lines[index]) {
        let line = index + 1
        items.append("\(openTag("li", line: line, annotate: annotate))\(MarkdownHTML.renderInline(itemText(lines[index])))</li>")
        index += 1
    }
    let tag = ordered ? "ol" : "ul"
    return "<\(tag)>" + items.joined() + "</\(tag)>"
}

private func isBlockStart(_ lines: [String], _ index: Int) -> Bool {
    let line = lines[index]
    return isFence(line) || headingLevel(line) != nil || line.hasPrefix(">") || isUnordered(line) || isOrdered(line) || isThematicBreak(line) || isTableStart(lines, index)
}

private func isFence(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
}

private func fenceMarker(_ line: String) -> String {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    let mark: Character = trimmed.first == "~" ? "~" : "`"
    return String(trimmed.prefix { $0 == mark })
}

private func fenceLanguage(_ line: String) -> String {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    let marker = fenceMarker(trimmed)
    return String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
}

private func closesFence(_ line: String, marker: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    return trimmed == marker || (trimmed.hasPrefix(marker) && trimmed.dropFirst(marker.count).allSatisfy(\.isWhitespace))
}

private func isThematicBreak(_ line: String) -> Bool {
    let compact = line.filter { !$0.isWhitespace }
    guard compact.count >= 3 else { return false }
    return compact.allSatisfy { $0 == "-" || $0 == "*" || $0 == "_" } && Set(compact).count == 1
}

private func headingLevel(_ line: String) -> Int? {
    let trimmed = line.drop { $0 == " " }
    var level = 0
    for character in trimmed {
        if character == "#" { level += 1 } else { break }
    }
    guard (1...6).contains(level) else { return nil }
    let rest = trimmed.dropFirst(level)
    if rest.isEmpty || rest.first == " " { return level }
    return nil
}

private func headingText(_ line: String) -> String {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    let level = headingLevel(trimmed) ?? 0
    var text = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
    while text.last == "#" { text.removeLast() }
    return text.trimmingCharacters(in: .whitespaces)
}

private func isUnordered(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard !isThematicBreak(trimmed) else { return false }
    return trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ")
}

private func isOrdered(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard let dot = trimmed.firstIndex(of: ".") else { return false }
    let number = trimmed[..<dot]
    guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return false }
    let rest = trimmed[trimmed.index(after: dot)...]
    return rest.first == " "
}

private func itemText(_ line: String) -> String {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if isOrdered(trimmed), let dot = trimmed.firstIndex(of: ".") {
        return trimmed[trimmed.index(after: dot)...].trimmingCharacters(in: .whitespaces)
    }
    return String(trimmed.dropFirst(2))
}

private func isTableStart(_ lines: [String], _ index: Int) -> Bool {
    guard index + 1 < lines.count else { return false }
    return looksLikeRow(lines[index]) && isSeparator(lines[index + 1])
}

private func looksLikeRow(_ line: String) -> Bool {
    line.contains("|") && !line.trimmingCharacters(in: .whitespaces).isEmpty
}

private func isSeparator(_ line: String) -> Bool {
    let cells = splitRow(line)
    guard !cells.isEmpty else { return false }
    return cells.allSatisfy { cell in
        let trimmed = cell.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("-") && trimmed.allSatisfy { $0 == "-" || $0 == ":" }
    }
}

private func splitRow(_ line: String) -> [String] {
    var text = line.trimmingCharacters(in: .whitespaces)
    if text.hasPrefix("|") { text.removeFirst() }
    if text.hasSuffix("|") { text.removeLast() }
    return text.split(separator: "|", omittingEmptySubsequences: false).map {
        $0.trimmingCharacters(in: .whitespaces)
    }
}

private func renderTable(header: [String], rows: [[String]]) -> String {
    let head = "<tr>" + header.map { "<th>\(MarkdownHTML.renderInline($0))</th>" }.joined() + "</tr>"
    let body = rows.map { row in
        "<tr>" + row.map { "<td>\(MarkdownHTML.renderInline($0))</td>" }.joined() + "</tr>"
    }.joined()
    return "<table><thead>\(head)</thead><tbody>\(body)</tbody></table>"
}

private func renderParagraph(_ lines: [String]) -> String {
    lines.enumerated().map { index, line in
        let body = MarkdownHTML.renderInline(line.trimmingCharacters(in: .whitespaces))
        if index < lines.count - 1 { return body + "<br>" }
        return body
    }.joined()
}

private func formatPlain(_ raw: String) -> String {
    var text = escape(raw)
    text = apply(text, pattern: #"!\[(.*?)\]\((.*?)\)"#) { groups in
        #"<img alt="\#(escapeAttr(groups[1]))" src="\#(escapeAttr(groups[2]))">"#
    }
    text = apply(text, pattern: #"\[(.*?)\]\((.*?)\)"#) { groups in
        let href = groups[2]
        if href.lowercased().hasPrefix("javascript:") { return escape(groups[1]) }
        return #"<a href="\#(escapeAttr(href))">\#(groups[1])</a>"#
    }
    text = apply(text, pattern: #"\*\*(.+?)\*\*"#) { "<strong>\($0[1])</strong>" }
    text = apply(text, pattern: #"__(.+?)__"#) { "<strong>\($0[1])</strong>" }
    text = apply(text, pattern: #"\*([^*]+)\*"#) { "<em>\($0[1])</em>" }
    text = apply(text, pattern: #"(^|[^\w])_([^_]+)_"#) { "\($0[1])<em>\($0[2])</em>" }
    return text
}

private func apply(_ text: String, pattern: String, transform: ([String]) -> String) -> String {
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
    let ns = text as NSString
    let range = NSRange(location: 0, length: ns.length)
    var result = ""
    var cursor = 0
    for match in expression.matches(in: text, range: range) {
        if match.range.location < cursor { continue }
        result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
        let groups = (0..<match.numberOfRanges).map { index -> String in
            let group = match.range(at: index)
            return group.location == NSNotFound ? "" : ns.substring(with: group)
        }
        result += transform(groups)
        cursor = match.range.location + match.range.length
    }
    if cursor < ns.length { result += ns.substring(from: cursor) }
    return result
}

private func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

private func escapeAttr(_ text: String) -> String {
    escape(text).replacingOccurrences(of: "\"", with: "&quot;")
}
