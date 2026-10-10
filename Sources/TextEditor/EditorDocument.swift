import AppKit
import EditorCore

extension Notification.Name {
    static let editorBookmarks = Notification.Name("editorBookmarks")
    static let editorEdited = Notification.Name("editorEdited")
    static let rebuildEditorMenu = Notification.Name("rebuildEditorMenu")
}

final class EditorDocument: ObservableObject, Identifiable {
    let id = UUID()
    let buffer = DocumentBuffer()
    @Published var path: URL?
    @Published var name: String
    @Published var encoding: TextEncoding
    @Published var language: Language
    @Published var eol: LineEnding
    @Published var dirty = false
    @Published var showPreview: Bool
    @Published var revision = 0
    var mtime: Date?
    /// 上次与磁盘一致时的正文。为空表示这份内容本来就还没保存。
    private var cleanBaseline: String?

    var text: String { buffer.storage.string }
    var bookmarks: [Int] = [] {
        didSet { NotificationCenter.default.post(name: .editorBookmarks, object: id) }
    }

    init(text: String, name: String, path: URL?, encoding: TextEncoding, eol: LineEnding, language: Language) {
        self.name = name
        self.path = path
        self.encoding = encoding
        self.eol = eol
        self.language = language
        self.showPreview = false
        buffer.owner = self
        buffer.replace(text, resetUndo: true)
        markClean()
    }

    func markClean() {
        cleanBaseline = text
        dirty = false
    }

    /// 当前正文本来就和磁盘不一致，撤销回打开时的内容仍然要保存。
    func discardCleanBaseline() {
        cleanBaseline = nil
        dirty = true
    }

    func markEdited() {
        if buffer.isApplyingUndo {
            reconcileUndo()
        } else if !dirty {
            dirty = true
        }
        revision += 1
        let count = buffer.lineCount
        let filtered = bookmarks.filter { $0 >= 1 && $0 <= count }
        if filtered != bookmarks { bookmarks = filtered }
        let editedID = id
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .editorEdited, object: editedID)
        }
    }

    func noteUndoRedo() {
        reconcileUndo()
    }

    private func reconcileUndo() {
        guard let cleanBaseline else { return }
        dirty = text != cleanBaseline
    }

    func adjustBookmarks(range: NSRange, replacement: String) {
        let change = buffer.lineChange(range: range, replacement: replacement)
        bookmarks = BookmarkAdjust.adjust(bookmarks, changes: [change])
    }

    func toggleBookmark(on line: Int) {
        if let index = bookmarks.firstIndex(of: line) {
            bookmarks.remove(at: index)
        } else {
            bookmarks.append(line)
            bookmarks.sort()
        }
    }

    func neighborBookmark(from line: Int, forward: Bool) -> Int? {
        let sorted = bookmarks.sorted()
        guard let first = sorted.first, let last = sorted.last else { return nil }
        if forward { return sorted.first { $0 > line } ?? first }
        return sorted.last { $0 < line } ?? last
    }

    static func untitled(name: String) -> EditorDocument {
        EditorDocument(text: "", name: name, path: nil, encoding: .utf8, eol: .lf, language: .plaintext)
    }
}

final class DocumentBuffer: NSObject, NSTextStorageDelegate {
    let storage = NSTextStorage()
    weak var owner: EditorDocument?
    private var suppressDepth = 0
    var font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    var isApplyingUndo: Bool {
        storage.layoutManagers.contains { manager in
            guard let undo = manager.firstTextView?.undoManager else { return false }
            return undo.isUndoing || undo.isRedoing
        }
    }
    private var lineStarts: [Int] = [0]
    private var lineStartsValid = false

    override init() {
        super.init()
        storage.delegate = self
    }

    func replace(_ text: String, resetUndo: Bool) {
        lineStartsValid = false
        suppressDepth += 1
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
        applyFont()
        storage.endEditing()
        suppressDepth -= 1
        if resetUndo {
            storage.layoutManagers.forEach { $0.firstTextView?.undoManager?.removeAllActions() }
        }
        Highlighter.apply(storage: storage, language: owner?.language ?? .plaintext)
        owner?.revision += 1
    }

    func applyFont() {
        let range = NSRange(location: 0, length: storage.length)
        guard range.length > 0 else { return }
        suppressDepth += 1
        storage.beginEditing()
        storage.addAttribute(.font, value: font, range: range)
        storage.endEditing()
        suppressDepth -= 1
    }

    var lineCount: Int {
        ensureLineStarts()
        return lineStarts.count
    }

    func position(at location: Int) -> (line: Int, column: Int) {
        ensureLineStarts()
        let loc = min(max(0, location), storage.length)
        var low = 0
        var high = lineStarts.count
        while low < high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= loc { low = mid + 1 } else { high = mid }
        }
        let lineIndex = max(0, low - 1)
        return (lineIndex + 1, loc - lineStarts[lineIndex] + 1)
    }

    func lineChange(range: NSRange, replacement: String) -> LineChange {
        let start = position(at: range.location)
        let end = position(at: range.location + range.length)
        return LineChange(
            startLine: start.line,
            endLine: end.line,
            startColumn: start.column,
            endColumn: end.column,
            text: replacement
        )
    }

    func rangeOfLine(_ line: Int) -> NSRange {
        ensureLineStarts()
        guard line >= 1, line <= lineStarts.count else {
            return NSRange(location: storage.length, length: 0)
        }
        return NSRange(location: lineStarts[line - 1], length: 0)
    }

    private func ensureLineStarts() {
        if lineStartsValid { return }
        let text = storage.string as NSString
        var starts = [0]
        starts.reserveCapacity(max(1, text.length / 40))
        var index = 0
        while index < text.length {
            if text.character(at: index) == 10 {
                starts.append(index + 1)
            }
            index += 1
        }
        lineStarts = starts
        lineStartsValid = true
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        if editedMask.contains(.editedCharacters) { lineStartsValid = false }
        guard suppressDepth == 0, editedMask.contains(.editedCharacters) else { return }
        owner?.markEdited()
    }
}
