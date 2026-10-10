import AppKit
import Darwin
import EditorCore
import SwiftUI

struct EditorKey: Hashable {
    var group: Int
    var id: UUID
}

final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var documents: [UUID: EditorDocument] = [:]
    @Published var groups: [EditorGroup] = [EditorGroup(), EditorGroup()]
    @Published var split = false
    @Published var activeGroup = 0
    @Published var theme: AppTheme = .light { didSet { persist(); restyle(); touch() } }
    @Published var wordWrap = false { didSet { persist(); touch() } }
    @Published var recent: [String] = [] { didSet { persist() } }
    @Published var findOpen = false { didSet { touch() } }
    @Published var findShowsReplace = false
    @Published var findQuery = ""
    @Published var findReplacement = ""
    @Published var findMatchCase = false
    @Published var findWholeWord = false
    @Published var findStatus = ""
    @Published var findFocus = 0
    @Published var cursorLine = 1
    @Published var cursorColumn = 1
    var fontSize: CGFloat = 13
    private var pinchAccum: CGFloat = 0

    private var loading = true
    private var prompting = false
    var allowClose = false
    weak var ui: AppUI?
    private var editors: [EditorKey: WeakView] = [:]
    private var watchers: [UUID: DispatchSourceFileSystemObject] = [:]
    private var missingConfirmed: Set<UUID> = []
    private var pendingMissing: [UUID] = []
    private var workspaceObserver: NSObjectProtocol?
    private var workspaceSaveWork: DispatchWorkItem?

    init() {
        let session = SessionStore.load()
        theme = session.theme
        wordWrap = session.wordWrap
        recent = session.recent
        let restored = restoreWorkspace()
        loading = false
        if !restored { newFile() }
        workspaceObserver = NotificationCenter.default.addObserver(
            forName: .editorEdited,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleWorkspaceSave()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(undoStateChanged), name: Notification.Name("NSUndoManagerDidUndoChangeNotification"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(undoStateChanged), name: Notification.Name("NSUndoManagerDidRedoChangeNotification"), object: nil)
    }

    @objc private func undoStateChanged() {
        for document in documents.values {
            let before = document.dirty
            document.noteUndoRedo()
            if document.dirty != before {
                NotificationCenter.default.post(name: .editorEdited, object: document.id)
            }
        }
    }

    func activeDocument() -> EditorDocument? { activeDocument(in: activeGroup) }

    func activeDocument(in group: Int) -> EditorDocument? {
        guard groups.indices.contains(group), let id = groups[group].activeID else { return nil }
        return documents[id]
    }

    var windowTitle: String {
        guard let document = activeDocument() else { return "Text Editor" }
        return "\(document.dirty ? "• " : "")\(document.name) — Text Editor"
    }

    func newFile() {
        let document = EditorDocument.untitled(name: applying(.plaintext, to: nextUntitled()))
        documents[document.id] = document
        groups[activeGroup].tabIDs.append(document.id)
        groups[activeGroup].activeID = document.id
        touch()
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.title = "打开"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        openURLs(panel.urls)
    }

    func openRecent(_ path: String) {
        openURLs([URL(fileURLWithPath: path)])
    }

    func openURLs(_ urls: [URL]) {
        var errors: [String] = []
        for url in urls {
            if let message = openFile(at: url) {
                errors.append("\(url.lastPathComponent)：\(message)")
            }
        }
        if !errors.isEmpty { alert("有文件没有打开", errors.joined(separator: "\n")) }
    }

    @discardableResult
    func openFile(at url: URL) -> String? {
        let standard = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standard.path, isDirectory: &isDirectory) else {
            removeRecent(standard)
            return "文件不存在"
        }
        if isDirectory.boolValue { return "只能打开文件" }
        if let existing = documents.values.first(where: { samePath($0.path, standard) }) {
            reveal(existing.id)
            return nil
        }
        do {
            let data = try Data(contentsOf: standard)
            let decoded = try TextCodec.read(data)
            let document = EditorDocument(
                text: decoded.text,
                name: standard.lastPathComponent,
                path: standard,
                encoding: decoded.encoding,
                eol: decoded.eol,
                language: Language.from(url: standard)
            )
            document.mtime = modificationDate(standard)
            document.showPreview = document.language == .markdown
            documents[document.id] = document
            groups[activeGroup].tabIDs.append(document.id)
            groups[activeGroup].activeID = document.id
            startWatching(document)
            addRecent(standard)
            findStatus = ""
            touch()
            return nil
        } catch {
            return describe(error)
        }
    }

    @discardableResult
    func saveActive() -> Bool {
        guard let document = activeDocument() else { return false }
        return save(document)
    }

    @discardableResult
    func save(_ document: EditorDocument) -> Bool {
        guard let path = document.path else { return saveAs(document) }
        return write(document, to: path, updateLanguage: false)
    }

    @discardableResult
    func saveAsActive() -> Bool {
        guard let document = activeDocument() else { return false }
        return saveAs(document)
    }

    @discardableResult
    func saveAs(_ document: EditorDocument) -> Bool {
        let panel = NSSavePanel()
        let types = SaveTypeController(language: document.language)
        panel.title = "另存为"
        panel.nameFieldStringValue = applying(document.language, to: document.path?.lastPathComponent ?? document.name)
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.delegate = types
        types.install(on: panel)
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        let standard = url.standardizedFileURL
        if documents.values.contains(where: { $0.id != document.id && samePath($0.path, standard) }) {
            alert("无法另存为", "该文件已在其他标签中打开。")
            return false
        }
        return write(document, to: standard, updateLanguage: true)
    }

    func closeActive() {
        guard let id = groups[activeGroup].activeID else { return }
        close(id: id)
    }

    @discardableResult
    func close(id: UUID, discardChanges: Bool = false) -> Bool {
        guard let document = documents[id] else { return true }
        if discardChanges { document.dirty = false }
        if document.dirty {
            switch askUnsaved(document) {
            case .cancel: return false
            case .discard: break
            case .save:
                if !save(document) { return false }
            }
        }
        for index in groups.indices {
            let position = groups[index].tabIDs.firstIndex(of: id)
            groups[index].tabIDs.removeAll { $0 == id }
            if groups[index].activeID == id {
                if let position, groups[index].tabIDs.indices.contains(position) {
                    groups[index].activeID = groups[index].tabIDs[position]
                } else {
                    groups[index].activeID = groups[index].tabIDs.last
                }
            }
        }
        stopWatching(id)
        missingConfirmed.remove(id)
        pendingMissing.removeAll { $0 == id }
        documents.removeValue(forKey: id)
        normalizeSplit()
        findStatus = ""
        touch()
        return true
    }

    func confirmCloseAll() -> Bool {
        if allowClose { return true }
        workspaceSaveWork?.cancel()
        saveWorkspace()
        allowClose = true
        return true
    }

    func selectTab(group: Int, id: UUID) {
        guard groups.indices.contains(group), groups[group].tabIDs.contains(id) else { return }
        groups[group].activeID = id
        activeGroup = group
        findStatus = ""
        if let textView = textView(group: group, id: id) {
            textView.window?.makeFirstResponder(textView)
            updateCursor(textView)
        }
        touch()
        if let document = documents[id], let path = document.path, !FileManager.default.fileExists(atPath: path.path) {
            askRemoved(document)
        }
    }

    func moveTab(id: UUID, from: Int, to: Int, index: Int) {
        guard groups.indices.contains(from), groups.indices.contains(to) else { return }
        if from != to, groups[to].tabIDs.contains(id) { return }
        guard let position = groups[from].tabIDs.firstIndex(of: id) else { return }
        groups[from].tabIDs.remove(at: position)
        if groups[from].activeID == id {
            if groups[from].tabIDs.isEmpty {
                groups[from].activeID = nil
            } else {
                groups[from].activeID = groups[from].tabIDs[min(position, groups[from].tabIDs.count - 1)]
            }
        }
        var insertAt = index
        if from == to, position < index { insertAt -= 1 }
        insertAt = max(0, min(insertAt, groups[to].tabIDs.count))
        groups[to].tabIDs.insert(id, at: insertAt)
        groups[to].activeID = id
        activeGroup = to
        normalizeSplit()
        touch()
    }

    func toggleSplit() {
        if split {
            let left = Set(groups[0].tabIDs)
            for id in groups[1].tabIDs where !left.contains(id) {
                groups[0].tabIDs.append(id)
            }
            if groups[0].activeID == nil { groups[0].activeID = groups[0].tabIDs.last }
            groups[1] = EditorGroup()
            split = false
            activeGroup = 0
        } else {
            split = true
            if groups[1].tabIDs.isEmpty, let id = groups[activeGroup].activeID ?? groups[0].activeID {
                groups[1].tabIDs = [id]
                groups[1].activeID = id
            }
            activeGroup = groups[1].activeID == nil ? 0 : 1
        }
        touch()
    }

    func togglePreview() {
        guard let document = activeDocument(), document.language == .markdown else { return }
        document.showPreview.toggle()
        touch()
    }

    func setLanguage(_ language: Language) {
        guard let document = activeDocument() else { return }
        let turningOn = language == .markdown && document.language != .markdown
        document.language = language
        if turningOn { document.showPreview = true }
        if language != .markdown { document.showPreview = false }
        if document.path == nil {
            document.name = applying(language, to: document.name)
        }
        Highlighter.apply(storage: document.buffer.storage, language: language)
        touch()
    }

    func checkMissingFiles() {
        for id in Array(documents.keys) {
            guard let document = documents[id] else { continue }
            guard let path = document.path else { continue }
            if FileManager.default.fileExists(atPath: path.path) {
                missingConfirmed.remove(id)
                if watchers[id] == nil { startWatching(document) }
                continue
            }
            askRemoved(document)
        }
    }

    func setEncoding(_ encoding: TextEncoding) {
        guard let document = activeDocument(), document.encoding != encoding else { return }
        guard let path = document.path else {
            document.encoding = encoding
            return
        }
        if document.dirty {
            let alert = NSAlert()
            alert.messageText = "更改编码"
            alert.informativeText = "文件已修改。继续后，保存时将使用新编码，当前正文保持不变。"
            alert.addButton(withTitle: "继续")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            document.encoding = encoding
            touch()
            return
        }
        do {
            let decoded = try TextCodec.decode(Data(contentsOf: path), as: encoding)
            document.encoding = encoding
            document.eol = decoded.eol
            document.mtime = modificationDate(path)
            document.bookmarks = []
            document.buffer.replace(decoded.text, resetUndo: true)
            document.markClean()
            touch()
        } catch {
            alert("无法按该编码重新读取", describe(error))
        }
    }

    func zoomIn() { setFontSize(fontSize + 1) }
    func zoomOut() { setFontSize(fontSize - 1) }
    func resetZoom() { setFontSize(13) }

    func zoom(by delta: CGFloat) {
        pinchAccum += delta
        let step: CGFloat = 0.12
        while pinchAccum >= step {
            pinchAccum -= step
            zoomIn()
        }
        while pinchAccum <= -step {
            pinchAccum += step
            zoomOut()
        }
    }

    private func setFontSize(_ size: CGFloat) {
        let next = min(28, max(9, size.rounded()))
        guard next != fontSize else { return }
        fontSize = next
        ui?.refreshDisplay()
    }

    func toggleBookmark() {
        guard let textView = activeTextView(), let document = activeDocument() else { return }
        let line = document.buffer.position(at: textView.selectedRange().location).line
        document.toggleBookmark(on: line)
    }

    func jumpBookmark(forward: Bool) {
        guard let textView = activeTextView(), let document = activeDocument() else { return }
        let line = document.buffer.position(at: textView.selectedRange().location).line
        guard let target = document.neighborBookmark(from: line, forward: forward) else { return }
        let range = document.buffer.rangeOfLine(target)
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        updateCursor(textView)
    }

    func openFind(replace: Bool) {
        guard activeDocument() != nil else { return }
        findShowsReplace = replace
        findFocus += 1
        if findOpen {
            touch()
        } else {
            findOpen = true
        }
    }

    func findNext(reverse: Bool) {
        let spots = searchSpots()
        guard !findQuery.isEmpty, !spots.isEmpty else {
            findStatus = ""
            return
        }
        let currentID = groups[activeGroup].activeID
        let currentIndex = spots.firstIndex { $0.group == activeGroup && $0.id == currentID }
            ?? spots.firstIndex { $0.id == currentID }
            ?? 0
        let current = spots[currentIndex]
        let selected = textView(group: current.group, id: current.id)?.selectedRange() ?? NSRange(location: 0, length: 0)
        let start = reverse ? selected.location : NSMaxRange(selected)
        if let found = matchInDocument(current.id, from: start, reverse: reverse) {
            showMatch(current, found, jumped: false)
            return
        }
        let count = spots.count
        if count > 1 {
            for step in 1..<count {
                let index = reverse
                    ? (currentIndex - step + count) % count
                    : (currentIndex + step) % count
                let spot = spots[index]
                guard let text = documents[spot.id]?.text as NSString? else { continue }
                let start = reverse ? text.length : 0
                if let found = match(in: text, from: start, reverse: reverse, wrap: false) {
                    showMatch(spot, found, jumped: true)
                    return
                }
            }
        }
        if let text = documents[current.id]?.text as NSString? {
            let start = reverse ? text.length : 0
            if let found = match(in: text, from: start, reverse: reverse, wrap: false) {
                showMatch(current, found, jumped: false)
                return
            }
        }
        findStatus = "未找到"
    }

    func replaceCurrent() {
        guard let textView = activeTextView(), !findQuery.isEmpty else { return }
        let selected = textView.selectedRange()
        if selected.length > 0 {
            let value = (textView.string as NSString).substring(with: selected)
            let same = findMatchCase ? value == findQuery : value.compare(findQuery, options: .caseInsensitive) == .orderedSame
            if same && (!findWholeWord || wholeWord(textView.string as NSString, selected)) {
                replace(textView, range: selected, with: findReplacement)
            }
        }
        findNext(reverse: false)
    }

    func replaceAll() {
        guard !findQuery.isEmpty else { return }
        var count = 0
        var files = 0
        for spot in searchSpots() {
            guard let textView = textView(group: spot.group, id: spot.id) else { continue }
            let ranges = allMatches(textView.string as NSString)
            guard !ranges.isEmpty else { continue }
            textView.undoManager?.beginUndoGrouping()
            for range in ranges.reversed() {
                replace(textView, range: range, with: findReplacement)
            }
            textView.undoManager?.endUndoGrouping()
            count += ranges.count
            files += 1
        }
        if count == 0 {
            findStatus = "未找到"
        } else if files > 1 {
            findStatus = "已在 \(files) 个标签中替换 \(count) 处"
        } else {
            findStatus = "已替换 \(count) 处"
        }
    }

    func sendEdit(_ selector: Selector) {
        NSApp.sendAction(selector, to: nil, from: nil)
    }

    func focus(group: Int, documentID: UUID) {
        guard groups.indices.contains(group) else { return }
        if groups[group].tabIDs.contains(documentID) {
            groups[group].activeID = documentID
        }
        activeGroup = group
    }

    func updateCursor(_ textView: NSTextView) {
        guard let document = activeDocument() else { return }
        let position = document.buffer.position(at: textView.selectedRange().location)
        cursorLine = position.line
        cursorColumn = position.column
        ui?.updateCursor()
    }

    func registerEditor(group: Int, id: UUID, view: NSTextView?) {
        let key = EditorKey(group: group, id: id)
        if let view {
            editors[key] = WeakView(view)
        } else {
            editors.removeValue(forKey: key)
        }
    }

    func recentLabel(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        let duplicated = recent.filter { URL(fileURLWithPath: $0).lastPathComponent == name }.count > 1
        if duplicated { return "\(name) — \(url.deletingLastPathComponent().lastPathComponent)" }
        return name
    }

    private func textView(group: Int, id: UUID) -> NSTextView? {
        let key = EditorKey(group: group, id: id)
        guard let view = editors[key]?.view else {
            editors.removeValue(forKey: key)
            return nil
        }
        return view
    }

    private func activeTextView() -> NSTextView? {
        guard let id = groups[activeGroup].activeID else { return nil }
        return textView(group: activeGroup, id: id)
    }

    private struct SearchSpot {
        var group: Int
        var id: UUID
    }

    private func searchSpots() -> [SearchSpot] {
        var seen = Set<UUID>()
        var spots: [SearchSpot] = []
        for group in [activeGroup, 1 - activeGroup] where groups.indices.contains(group) {
            for id in groups[group].tabIDs where seen.insert(id).inserted {
                spots.append(SearchSpot(group: group, id: id))
            }
        }
        return spots
    }

    private func matchInDocument(_ id: UUID, from start: Int, reverse: Bool) -> NSRange? {
        guard let text = documents[id]?.text as NSString? else { return nil }
        return match(in: text, from: start, reverse: reverse, wrap: false)
    }

    private func showMatch(_ spot: SearchSpot, _ range: NSRange, jumped: Bool) {
        if activeGroup != spot.group || groups[spot.group].activeID != spot.id {
            selectTab(group: spot.group, id: spot.id)
        }
        guard let textView = textView(group: spot.group, id: spot.id) else { return }
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        textView.showFindIndicator(for: range)
        if jumped, let name = documents[spot.id]?.name {
            findStatus = "在「\(name)」中"
        } else {
            findStatus = ""
        }
        updateCursor(textView)
    }

    private func write(_ document: EditorDocument, to url: URL, updateLanguage: Bool) -> Bool {
        if document.path.map({ samePath($0, url) }) == true,
           let previous = document.mtime,
           let current = modificationDate(url),
           current.timeIntervalSince(previous) > 0.001 {
            let alert = NSAlert()
            alert.messageText = "文件已被其他程序修改"
            alert.informativeText = document.name
            alert.addButton(withTitle: "覆盖")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
        }
        do {
            let data = try TextCodec.encode(document.text, encoding: document.encoding, eol: document.eol)
            try data.write(to: url, options: .atomic)
            document.path = url
            document.name = url.lastPathComponent
            document.mtime = modificationDate(url)
            document.markClean()
            if updateLanguage {
                document.language = Language.from(url: url)
                Highlighter.apply(storage: document.buffer.storage, language: document.language)
            }
            addRecent(url)
            startWatching(document)
            touch()
            return true
        } catch {
            alert("无法保存", describe(error))
            return false
        }
    }

    private func reveal(_ id: UUID) {
        if groups[activeGroup].tabIDs.contains(id) {
            selectTab(group: activeGroup, id: id)
            return
        }
        if let group = groups.indices.first(where: { groups[$0].tabIDs.contains(id) }) {
            if group == 1 { split = true }
            selectTab(group: group, id: id)
        }
    }

    private func normalizeSplit() {
        if groups[1].tabIDs.isEmpty {
            split = false
            activeGroup = 0
            return
        }
        if groups[0].tabIDs.isEmpty {
            groups[0] = groups[1]
            groups[1] = EditorGroup()
            split = false
            activeGroup = 0
        }
    }

    private func nextUntitled() -> String {
        let names = Set(documents.values.map { untitledBase($0.name) })
        if !names.contains("未命名") { return "未命名" }
        var index = 2
        while names.contains("未命名 \(index)") { index += 1 }
        return "未命名 \(index)"
    }

    private func untitledBase(_ name: String) -> String {
        let file = name as NSString
        guard isLanguageExtension(file.pathExtension) else { return name }
        return file.deletingPathExtension
    }

    fileprivate func applying(_ language: Language, to filename: String) -> String {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let file = trimmed as NSString
        let ext = file.pathExtension
        if language.acceptsExtension(ext) { return trimmed }
        let base: String
        if ext.isEmpty || isLanguageExtension(ext) {
            base = ext.isEmpty ? trimmed : file.deletingPathExtension
        } else {
            base = trimmed
        }
        guard !base.isEmpty else { return trimmed }
        return "\(base).\(language.preferredExtension)"
    }

    private func isLanguageExtension(_ ext: String) -> Bool {
        let lower = ext.lowercased()
        guard !lower.isEmpty else { return false }
        if lower == "txt" { return true }
        return Language.from(url: URL(fileURLWithPath: "x.\(lower)")) != .plaintext
    }

    private func addRecent(_ url: URL) {
        let path = url.standardizedFileURL.path
        recent.removeAll { $0 == path }
        recent.insert(path, at: 0)
        if recent.count > 10 { recent = Array(recent.prefix(10)) }
    }

    private func removeRecent(_ url: URL) {
        let path = url.standardizedFileURL.path
        recent.removeAll { $0 == path }
    }

    private func touch() {
        guard !loading else { return }
        ui?.reload()
        scheduleWorkspaceSave()
    }

    private func scheduleWorkspaceSave() {
        guard !loading else { return }
        workspaceSaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveWorkspace()
        }
        workspaceSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func saveWorkspace() {
        guard !loading else { return }
        var seen = Set<UUID>()
        var files: [WorkspaceFile] = []
        var active = 0
        let activeID = groups[activeGroup].activeID
        for id in groups[0].tabIDs + groups[1].tabIDs where seen.insert(id).inserted {
            guard let document = documents[id] else { continue }
            if document.id == activeID { active = files.count }
            files.append(WorkspaceFile(
                name: document.name,
                path: document.path?.path,
                text: document.text,
                encoding: document.encoding.rawValue,
                eol: document.eol.rawValue,
                language: document.language.rawValue,
                dirty: document.dirty,
                bookmarks: document.bookmarks,
                showPreview: document.showPreview
            ))
        }
        WorkspaceStore.save(WorkspaceSnapshot(files: files, active: active))
    }

    private func restoreWorkspace() -> Bool {
        guard let snapshot = WorkspaceStore.load(), !snapshot.files.isEmpty else { return false }
        var ids: [UUID] = []
        for file in snapshot.files {
            let encoding = TextEncoding(rawValue: file.encoding) ?? .utf8
            let eol = LineEnding(rawValue: file.eol) ?? .lf
            let language = Language(rawValue: file.language) ?? .plaintext
            let path = file.path.map { URL(fileURLWithPath: $0).standardizedFileURL }
            var text = file.text
            let dirty = file.dirty
            if !dirty, let path, FileManager.default.fileExists(atPath: path.path),
               let data = try? Data(contentsOf: path),
               let decoded = try? TextCodec.read(data) {
                text = decoded.text
            }
            let document = EditorDocument(
                text: text,
                name: file.name,
                path: path,
                encoding: encoding,
                eol: eol,
                language: language
            )
            if dirty { document.discardCleanBaseline() }
            document.bookmarks = file.bookmarks
            document.showPreview = file.showPreview ?? (language == .markdown)
            if let path { document.mtime = modificationDate(path) }
            documents[document.id] = document
            ids.append(document.id)
            if path != nil { startWatching(document) }
        }
        guard !ids.isEmpty else { return false }
        groups[0].tabIDs = ids
        groups[0].activeID = ids[min(max(0, snapshot.active), ids.count - 1)]
        activeGroup = 0
        return true
    }

    private func persist() {
        guard !loading else { return }
        SessionStore.save(SessionSettings(theme: theme, wordWrap: wordWrap, recent: recent))
    }

    private func restyle() {
        guard !loading else { return }
        for document in documents.values {
            Highlighter.apply(storage: document.buffer.storage, language: document.language)
        }
    }

    private func askUnsaved(_ document: EditorDocument) -> CloseChoice {
        let alert = NSAlert()
        alert.messageText = "是否保存对「\(document.name)」的更改？"
        alert.informativeText = "不保存的话，这些更改会丢失。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "不保存")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .save
        case .alertSecondButtonReturn: return .discard
        default: return .cancel
        }
    }

    private func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func describe(_ error: Error) -> String {
        if error is CodecError { return "无法用该编码读取此文件" }
        let ns = error as NSError
        switch (ns.domain, ns.code) {
        case (NSCocoaErrorDomain, NSFileNoSuchFileError), (NSCocoaErrorDomain, NSFileReadNoSuchFileError):
            return "文件不存在"
        case (NSCocoaErrorDomain, NSFileReadNoPermissionError), (NSCocoaErrorDomain, NSFileWriteNoPermissionError):
            return "没有权限访问该文件"
        case (NSCocoaErrorDomain, NSFileWriteOutOfSpaceError):
            return "磁盘已满"
        default:
            return ns.localizedDescription
        }
    }

    private func modificationDate(_ url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    private func startWatching(_ document: EditorDocument) {
        stopWatching(document.id)
        guard let path = document.path?.path else { return }
        let fd = Darwin.open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.delete, .rename, .revoke],
            queue: .main
        )
        let id = document.id
        source.setEventHandler { [weak self] in
            self?.handleFileEvent(id)
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        source.resume()
        watchers[id] = source
    }

    private func stopWatching(_ id: UUID) {
        watchers[id]?.cancel()
        watchers.removeValue(forKey: id)
    }

    private var refreshingWatch = false

    private func handleFileEvent(_ id: UUID) {
        guard !refreshingWatch else { return }
        guard let document = documents[id], let path = document.path else { return }
        if FileManager.default.fileExists(atPath: path.path) {
            missingConfirmed.remove(id)
            refreshingWatch = true
            startWatching(document)
            refreshingWatch = false
            return
        }
        stopWatching(id)
        askRemoved(document)
    }

    private func askRemoved(_ document: EditorDocument) {
        guard documents[document.id] != nil, let path = document.path else { return }
        if FileManager.default.fileExists(atPath: path.path) {
            missingConfirmed.remove(document.id)
            if watchers[document.id] == nil { startWatching(document) }
            return
        }
        if missingConfirmed.contains(document.id) { return }
        if prompting {
            if !pendingMissing.contains(document.id) { pendingMissing.append(document.id) }
            return
        }
        prompting = true
        let alert = NSAlert()
        alert.messageText = "「\(document.name)」已被删除"
        alert.informativeText = "是否从编辑器中移除？"
        alert.addButton(withTitle: "移除")
        alert.addButton(withTitle: "保留")
        let remove = alert.runModal() == .alertFirstButtonReturn
        prompting = false
        guard documents[document.id] != nil else {
            flushPendingMissing()
            return
        }
        if remove {
            close(id: document.id, discardChanges: true)
        } else {
            missingConfirmed.insert(document.id)
            document.discardCleanBaseline()
            touch()
        }
        flushPendingMissing()
    }

    private func flushPendingMissing() {
        guard !prompting, !pendingMissing.isEmpty else { return }
        let id = pendingMissing.removeFirst()
        guard let document = documents[id] else {
            flushPendingMissing()
            return
        }
        askRemoved(document)
    }

    private func samePath(_ lhs: URL?, _ rhs: URL) -> Bool {
        lhs?.standardizedFileURL.path == rhs.standardizedFileURL.path
    }

    private func match(in text: NSString, from start: Int, reverse: Bool, wrap: Bool) -> NSRange? {
        let options: NSString.CompareOptions = findMatchCase ? [] : [.caseInsensitive]
        func scan(_ range: NSRange, backwards: Bool) -> NSRange? {
            guard range.length > 0 else { return nil }
            var window = range
            let opts = backwards ? options.union(.backwards) : options
            while window.length > 0 {
                let found = text.range(of: findQuery, options: opts, range: window)
                if found.location == NSNotFound { return nil }
                if !findWholeWord || wholeWord(text, found) { return found }
                if backwards {
                    if found.location <= window.location { return nil }
                    window.length = found.location - window.location
                } else {
                    let next = max(NSMaxRange(found), found.location + 1)
                    let end = NSMaxRange(window)
                    if next >= end { return nil }
                    window = NSRange(location: next, length: end - next)
                }
            }
            return nil
        }
        let length = text.length
        let origin = min(max(0, start), length)
        if !reverse {
            if let found = scan(NSRange(location: origin, length: length - origin), backwards: false) { return found }
            if wrap { return scan(NSRange(location: 0, length: origin), backwards: false) }
        } else {
            if let found = scan(NSRange(location: 0, length: origin), backwards: true) { return found }
            if wrap { return scan(NSRange(location: 0, length: length), backwards: true) }
        }
        return nil
    }

    private func allMatches(_ text: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var cursor = 0
        while let found = match(in: text, from: cursor, reverse: false, wrap: false) {
            if found.location < cursor { break }
            ranges.append(found)
            let next = max(NSMaxRange(found), found.location + 1)
            if next <= cursor || next > text.length { break }
            cursor = next
        }
        return ranges
    }

    private func wholeWord(_ text: NSString, _ range: NSRange) -> Bool {
        func boundary(_ index: Int) -> Bool {
            if index < 0 || index >= text.length { return true }
            let value = text.character(at: index)
            if value == 95 { return false }
            guard let scalar = UnicodeScalar(UInt32(value)) else { return true }
            return !CharacterSet.alphanumerics.contains(scalar)
        }
        return boundary(range.location - 1) && boundary(NSMaxRange(range))
    }

    private func replace(_ textView: NSTextView, range: NSRange, with text: String) {
        guard textView.shouldChangeText(in: range, replacementString: text) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: text)
        textView.didChangeText()
    }
}

struct EditorGroup: Identifiable, Equatable {
    let id = UUID()
    var tabIDs: [UUID] = []
    var activeID: UUID?
}

private enum CloseChoice {
    case save, discard, cancel
}

protocol AppUI: AnyObject {
    func reload()
    func refreshDisplay()
    func noteEdit(_ id: UUID)
    func updateCursor()
}

private final class WeakView {
    weak var view: NSTextView?
    init(_ view: NSTextView) { self.view = view }
}

extension Language {
    var preferredExtension: String {
        switch self {
        case .plaintext: return "txt"
        case .markdown: return "md"
        case .json: return "json"
        case .html: return "html"
        case .css: return "css"
        case .javascript: return "js"
        case .typescript: return "ts"
        case .python: return "py"
        case .xml: return "xml"
        case .sql: return "sql"
        case .shell: return "sh"
        case .yaml: return "yaml"
        case .cpp: return "cpp"
        case .csharp: return "cs"
        case .java: return "java"
        }
    }

    func acceptsExtension(_ ext: String) -> Bool {
        let lower = ext.lowercased()
        guard !lower.isEmpty else { return false }
        if self == .plaintext { return lower == "txt" }
        return Language.from(url: URL(fileURLWithPath: "x.\(lower)")) == self
    }
}

private final class SaveTypeController: NSObject, NSOpenSavePanelDelegate {
    let popup = NSPopUpButton()
    private var language: Language
    private weak var panel: NSSavePanel?

    init(language: Language) {
        self.language = language
        super.init()
        popup.target = self
        popup.action = #selector(typeChanged)
        for item in Language.allCases {
            popup.addItem(withTitle: "\(item.label) (.\(item.preferredExtension))")
            popup.lastItem?.representedObject = item.rawValue
        }
        if let index = Language.allCases.firstIndex(of: language) {
            popup.selectItem(at: index)
        }
    }

    func install(on panel: NSSavePanel) {
        self.panel = panel
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 36))
        let label = NSTextField(labelWithString: "文件类型：")
        label.frame = NSRect(x: 0, y: 8, width: 72, height: 20)
        popup.frame = NSRect(x: 74, y: 4, width: 260, height: 26)
        container.addSubview(label)
        container.addSubview(popup)
        panel.accessoryView = container
    }

    @objc private func typeChanged() {
        guard let raw = popup.selectedItem?.representedObject as? String,
              let language = Language(rawValue: raw),
              let panel else { return }
        self.language = language
        panel.nameFieldStringValue = AppModel.shared.applying(language, to: panel.nameFieldStringValue)
    }

    func panel(_ sender: Any, userEnteredFilename filename: String, confirmed okFlag: Bool) -> String? {
        guard okFlag else { return filename }
        return AppModel.shared.applying(language, to: filename)
    }
}
