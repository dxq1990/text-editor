import AppKit
import EditorCore

@main
enum TextEditorMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel.shared
    var window: NSWindow!
    var root: RootView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        root = RootView(model: model)
        model.ui = root
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 760, height: 480)
        window.title = model.windowTitle
        window.contentView = root
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        installMenu()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshMenu), name: .rebuildEditorMenu, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(commitPinyinForMenu), name: NSMenu.didBeginTrackingNotification, object: nil)
        root.reload()
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(root.left.currentTextView)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.checkMissingFiles()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        model.openURLs(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.confirmCloseAll() ? .terminateNow : .terminateCancel
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        model.confirmCloseAll()
    }

    @objc private func refreshMenu() { installMenu() }

    @objc private func commitPinyinForMenu() {
        PlainTextView.commitMarkedPinyin()
    }

    private func installMenu() {
        let main = NSMenu()
        let quit = item("退出", #selector(NSApplication.terminate(_:)), "q")
        quit.target = NSApp
        main.addItem(menu(modelName(), [quit]))
        main.addItem(menu("文件", [
            item("新建", #selector(newFile), "n"),
            item("打开…", #selector(openFile), "o"),
            recentMenu(),
            .separator(),
            item("保存", #selector(saveFile), "s"),
            item("另存为…", #selector(saveAs), "S"),
            .separator(),
            item("关闭标签", #selector(closeTab), "w")
        ]))
        main.addItem(menu("编辑", [
            item("撤销", #selector(undoEdit), "z"),
            item("重做", #selector(redoEdit), "Z"),
            .separator(),
            item("剪切", #selector(cutEdit), "x"),
            item("复制", #selector(copyEdit), "c"),
            item("粘贴", #selector(pasteEdit), "v"),
            item("全选", #selector(selectAllEdit), "a")
        ]))
        main.addItem(menu("搜索", [
            item("查找", #selector(find), "f"),
            item("替换", #selector(replace), nil),
            item("查找下一个", #selector(findNext), "g"),
            item("查找上一个", #selector(findPrevious), "G")
        ]))
        main.addItem(menu("视图", [
            item("自动换行", #selector(toggleWrap), nil),
            .separator(),
            item("放大", #selector(zoomIn), "="),
            item("缩小", #selector(zoomOut), "-"),
            item("实际大小", #selector(resetZoom), "0"),
            .separator(),
            item("浅色主题", #selector(lightTheme), nil),
            item("深色主题", #selector(darkTheme), nil),
            .separator(),
            item("Markdown 预览", #selector(togglePreview), nil)
        ]))
        let languages = NSMenu()
        for language in Language.allCases {
            let entry = languages.addItem(withTitle: language.label, action: #selector(chooseLanguage(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = language.rawValue
        }
        let languageItem = NSMenuItem(title: "语言", action: nil, keyEquivalent: "")
        languageItem.submenu = languages
        main.addItem(languageItem)
        NSApp.mainMenu = main
    }

    private func recentMenu() -> NSMenuItem {
        let submenu = NSMenu()
        if model.recent.isEmpty {
            submenu.addItem(withTitle: "（无）", action: nil, keyEquivalent: "")
        } else {
            for path in model.recent {
                let entry = submenu.addItem(withTitle: model.recentLabel(path), action: #selector(openRecent(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = path
            }
        }
        let item = NSMenuItem(title: "打开最近", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func menu(_ title: String, _ entries: [NSMenuItem]) -> NSMenuItem {
        let submenu = NSMenu(title: title)
        entries.forEach { submenu.addItem($0) }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func item(_ title: String, _ action: Selector, _ key: String?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key ?? "")
        item.target = self
        if key == "S" || key == "Z" || key == "G" || key == "B" {
            item.keyEquivalentModifierMask = [.command, .shift]
            item.keyEquivalent = key!.lowercased()
        }
        return item
    }

    private func modelName() -> String { "Text Editor" }

    @objc private func newFile() { model.newFile() }
    @objc private func openFile() { model.openPanel() }
    @objc private func saveFile() { model.saveActive() }
    @objc private func saveAs() { model.saveAsActive() }
    @objc private func closeTab() { model.closeActive() }
    @objc private func undoEdit() { model.sendEdit(Selector(("undo:"))) }
    @objc private func redoEdit() { model.sendEdit(Selector(("redo:"))) }
    @objc private func cutEdit() { model.sendEdit(#selector(NSText.cut(_:))) }
    @objc private func copyEdit() { model.sendEdit(#selector(NSText.copy(_:))) }
    @objc private func pasteEdit() { model.sendEdit(#selector(NSText.paste(_:))) }
    @objc private func selectAllEdit() { model.sendEdit(#selector(NSText.selectAll(_:))) }
    @objc private func find() { model.openFind(replace: false) }
    @objc private func replace() { model.openFind(replace: true) }
    @objc private func findNext() { model.findNext(reverse: false) }
    @objc private func findPrevious() { model.findNext(reverse: true) }
    @objc private func toggleWrap() { model.wordWrap.toggle() }
    @objc private func lightTheme() { model.theme = .light }
    @objc private func darkTheme() { model.theme = .dark }
    @objc private func togglePreview() { model.togglePreview() }
    @objc private func zoomIn() { model.zoomIn() }
    @objc private func zoomOut() { model.zoomOut() }
    @objc private func resetZoom() { model.resetZoom() }
    @objc private func chooseLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let language = Language(rawValue: raw) else { return }
        model.setLanguage(language)
    }
    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        model.openRecent(path)
    }
}
