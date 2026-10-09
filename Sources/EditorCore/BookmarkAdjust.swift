import Foundation

public struct LineChange: Equatable, Sendable {
    public var startLine: Int
    public var endLine: Int
    public var startColumn: Int
    public var endColumn: Int
    public var text: String

    public init(startLine: Int, endLine: Int, startColumn: Int, endColumn: Int, text: String) {
        self.startLine = startLine
        self.endLine = endLine
        self.startColumn = startColumn
        self.endColumn = endColumn
        self.text = text
    }
}

public enum BookmarkAdjust {
    public static func adjust(_ lines: [Int], changes: [LineChange]) -> [Int] {
        var next: [Int] = []
        for line in lines {
            if let mapped = mapLine(line, changes: changes), mapped >= 1 {
                next.append(mapped)
            }
        }
        return Array(Set(next)).sorted()
    }

    private static func addedBreaks(_ text: String) -> Int {
        if text.isEmpty { return 0 }
        return text.split(separator: "\n", omittingEmptySubsequences: false).count - 1
    }

    private static func mapLine(_ line: Int, changes: [LineChange]) -> Int? {
        var shift = 0
        for change in changes {
            let added = addedBreaks(change.text)
            let removed = change.endLine - change.startLine
            let delta = added - removed
            if line < change.startLine { continue }

            let pureInsertion = change.startLine == change.endLine && change.startColumn == change.endColumn
            if pureInsertion {
                if line > change.startLine {
                    shift += delta
                } else if line == change.startLine && change.startColumn == 1 && added > 0 {
                    shift += added
                }
                continue
            }

            if line > change.endLine {
                shift += delta
                continue
            }
            if line > change.startLine && line < change.endLine { return nil }
            if line == change.endLine && line != change.startLine {
                if change.endColumn == 1 {
                    shift += delta
                    continue
                }
                return nil
            }
            if line == change.startLine && change.startColumn == 1 && change.endLine > change.startLine && change.endColumn == 1 && added == 0 {
                return nil
            }
        }
        return line + shift
    }
}
