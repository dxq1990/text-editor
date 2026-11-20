import AppKit
import EditorCore
import WebKit

final class PreviewController: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    var onScrollLine: ((Int) -> Void)?
    var onEditMarkdown: ((String) -> Void)?
    var onSave: (() -> Void)?
    private let bridge = ScriptBridge()
    private static let shellVersion = "md-placeholders-7"
    private var body = ""
    private var theme = AppTheme.light
    private var basePath = ""
    private var loadedShellVersion = ""
    private var ready = false
    private var anchorLine = 1
    private var ignoringPreviewScroll = false
    private var ignoreReloadUntil = Date.distantPast

    override init() {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        config.userContentController = controller
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        bridge.owner = self
        controller.add(bridge, name: "previewScroll")
        controller.add(bridge, name: "previewEdit")
        controller.add(bridge, name: "previewSave")
        webView.navigationDelegate = self
    }

    func update(body: String, theme: AppTheme, baseURL: URL?, anchorLine: Int) {
        let path = baseURL?.absoluteString ?? ""
        let baseChanged = path != basePath
        self.body = body
        self.theme = theme
        self.basePath = path
        self.anchorLine = max(1, anchorLine)
        if Date() < ignoreReloadUntil {
            return
        }
        let shellChanged = loadedShellVersion != Self.shellVersion
        if baseChanged || !ready || shellChanged {
            ready = false
            loadedShellVersion = Self.shellVersion
            webView.loadHTMLString(previewShell(baseURL: baseURL), baseURL: baseURL)
        } else {
            push()
        }
    }

    func scrollToLine(_ line: Int) {
        let next = max(1, line)
        anchorLine = next
        ignoringPreviewScroll = true
        webView.evaluateJavaScript("scrollToLine(\(next))", completionHandler: { [weak self] _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                self?.ignoringPreviewScroll = false
            }
        })
    }

    func receive(_ message: WKScriptMessage) {
        switch message.name {
        case "previewScroll":
            let line: Int
            if let value = message.body as? Int {
                line = value
            } else if let value = message.body as? Double {
                line = Int(value)
            } else {
                return
            }
            guard !ignoringPreviewScroll else { return }
            anchorLine = line
            onScrollLine?(line)
        case "previewEdit":
            guard let markdown = message.body as? String else { return }
            ignoreReloadUntil = Date().addingTimeInterval(0.6)
            onEditMarkdown?(markdown)
        case "previewSave":
            onSave?()
        default:
            break
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        push()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    private func push() {
        guard ready,
              let data = try? JSONSerialization.data(withJSONObject: [body, theme.rawValue]),
              let payload = String(data: data, encoding: .utf8) else { return }
        let line = anchorLine
        ignoringPreviewScroll = true
        webView.evaluateJavaScript("render.apply(null, \(payload))", completionHandler: { [weak self] _, _ in
            self?.webView.evaluateJavaScript("scrollToLine(\(line))", completionHandler: { [weak self] _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    self?.ignoringPreviewScroll = false
                }
            })
        })
    }
}

private final class ScriptBridge: NSObject, WKScriptMessageHandler {
    weak var owner: PreviewController?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.receive(message)
    }
}

private func previewShell(baseURL: URL?) -> String {
    let base = baseURL.map { "<base href=\"\($0.absoluteString)\">" } ?? ""
    return """
    <!doctype html>
    <html>
    <head>
    <meta charset="utf-8">
    \(base)
    <style>
      :root {
        color-scheme: light;
        --page: #f3f3f3;
        --paper: #ffffff;
        --fg: #1f1f1f;
        --muted: #6a6a6a;
        --line: #e6e6e6;
        --code: #f4f4f4;
        --inline: #efefef;
        --link: #4078c0;
        --toc: #e8e8e8;
        --ph: #b0b0b0;
        --shadow: 0 1px 2px rgba(0,0,0,0.04), 0 4px 16px rgba(0,0,0,0.04);
      }
      :root[data-theme="dark"] {
        color-scheme: dark;
        --page: #1b1b1b;
        --paper: #242424;
        --fg: #ececec;
        --muted: #9a9a9a;
        --line: #333333;
        --code: #2e2e2e;
        --inline: #333333;
        --link: #6db3f2;
        --toc: #202020;
        --ph: #6f6f6f;
        --shadow: 0 1px 2px rgba(0,0,0,0.25), 0 8px 24px rgba(0,0,0,0.28);
      }
      html, body { margin: 0; height: 100%; background: var(--page); color: var(--fg); }
      body {
        font: 16px/1.65 -apple-system, "PingFang SC", "Hiragino Sans GB", "Segoe UI", sans-serif;
        min-height: 100vh;
      }
      body.has-toc {
        display: flex;
        height: 100vh;
        overflow: hidden;
      }
      #toc {
        box-sizing: border-box;
        flex: 0 0 260px;
        width: 260px;
        height: 100vh;
        overflow: auto;
        background: var(--toc);
        border-right: 1px solid var(--line);
        padding: 18px 14px 28px;
        font-size: 13px;
        line-height: 1.45;
      }
      #toc[hidden] { display: none !important; }
      body.toc-collapsed #toc {
        flex-basis: 48px;
        width: 48px;
        padding: 14px 6px;
      }
      .toc-head {
        display: flex; align-items: center; justify-content: space-between; gap: 6px;
        position: sticky; top: 0; z-index: 1;
        margin: 0 0 14px; padding: 0 2px 12px; border-bottom: 1px solid var(--line);
        background: var(--toc); color: var(--fg); font-size: 13px; font-weight: 600;
      }
      #toc-toggle {
        border: 0; background: transparent; color: var(--muted); cursor: pointer;
        font: inherit; padding: 2px 4px; border-radius: 4px;
      }
      #toc-toggle:hover { color: var(--fg); background: var(--code); }
      #toc-list { display: flex; flex-direction: column; gap: 2px; }
      body.toc-collapsed .toc-head span,
      body.toc-collapsed #toc-list { display: none; }
      body.toc-collapsed .toc-head { border: 0; margin: 0; padding: 0; justify-content: center; }
      .toc-item {
        display: block; width: 100%; box-sizing: border-box; border: 0; background: transparent;
        color: var(--muted); text-align: left; cursor: pointer; font: inherit;
        padding: 8px 10px; border-radius: 6px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
      }
      .toc-item:hover { color: var(--fg); background: var(--code); }
      .toc-item.active { color: var(--link); background: var(--code); }
      .toc-h1 { font-weight: 600; color: var(--fg); padding-left: 8px; }
      .toc-h2 { padding-left: 16px; }
      .toc-h3 { padding-left: 24px; }
      .toc-h4 { padding-left: 32px; }
      .toc-h5 { padding-left: 40px; }
      .toc-h6 { padding-left: 48px; }
      #main {
        flex: 1 1 auto;
        min-width: 0;
        height: 100vh;
        overflow: auto;
        background: var(--page);
      }
      body:not(.has-toc) #main {
        height: auto;
        min-height: 100vh;
        overflow: visible;
      }
      #page {
        box-sizing: border-box;
        width: min(960px, calc(100% - 64px));
        margin: 28px auto 48px;
        background: var(--paper);
        border-radius: 10px;
        box-shadow: var(--shadow);
        min-height: calc(100vh - 76px);
      }
      article {
        box-sizing: border-box; width: 100%; min-width: 0; padding: 44px 56px 72px; outline: none;
      }
      article:focus { outline: none; }
      h1, h2, h3, h4, h5, h6, p, li, blockquote { overflow-wrap: break-word; }
      h1, h2, h3, h4, h5, h6 {
        color: var(--fg); line-height: 1.35; margin: 1.35em 0 0.5em; font-weight: 700;
        scroll-margin-top: 16px;
      }
      h1 { font-size: 1.85em; margin-top: 0.2em; }
      h2 { font-size: 1.35em; }
      h3 { font-size: 1.15em; }
      h1.is-empty,
      h2.is-empty,
      h3.is-empty,
      h4.is-empty,
      h5.is-empty,
      h6.is-empty,
      p.is-empty,
      li.is-empty,
      blockquote.is-empty {
        position: relative;
        min-height: 1.2em;
      }
      h1.is-empty::before,
      h2.is-empty::before,
      h3.is-empty::before,
      h4.is-empty::before,
      h5.is-empty::before,
      h6.is-empty::before,
      p.is-empty::before,
      li.is-empty::before,
      blockquote.is-empty::before {
        position: absolute;
        left: 0;
        top: 0;
        color: var(--ph);
        pointer-events: none;
        white-space: nowrap;
        font-weight: inherit;
      }
      h1.is-empty::before { content: "标题 1"; }
      h2.is-empty::before { content: "标题 2"; }
      h3.is-empty::before { content: "标题 3"; }
      h4.is-empty::before { content: "标题 4"; }
      h5.is-empty::before { content: "标题 5"; }
      h6.is-empty::before { content: "标题 6"; }
      p.is-empty::before { content: "输入正文"; font-weight: 400; }
      li.is-empty::before { content: "列表项"; font-weight: 400; }
      blockquote.is-empty::before { content: "引用文字"; font-weight: 400; }
      p, ul, ol, pre, table, blockquote { margin: 0.85em 0; }
      a { color: var(--link); text-decoration: none; }
      a:hover { text-decoration: underline; }
      code {
        font-family: ui-monospace, Menlo, Consolas, monospace; font-size: 0.9em;
        background: var(--inline); padding: 0.12em 0.4em; border-radius: 4px;
      }
      pre {
        background: var(--code); padding: 14px 16px; border-radius: 8px; overflow: auto;
        font-size: 0.92em; line-height: 1.55;
      }
      pre code { background: none; padding: 0; font-size: inherit; }
      blockquote {
        margin-left: 0; padding: 2px 0 2px 14px; border-left: 3px solid var(--line); color: var(--muted);
      }
      table { border-collapse: collapse; width: 100%; }
      th, td { border: 1px solid var(--line); padding: 8px 10px; text-align: left; }
      th { background: var(--code); }
      img { max-width: 100%; }
      hr { border: 0; border-top: 1px solid var(--line); margin: 1.6em 0; }
      ul, ol { padding-left: 1.4em; }
    </style>
    </head>
    <body>
    <nav id="toc" hidden>
      <div class="toc-head">
        <span>目录</span>
        <button type="button" id="toc-toggle" title="折叠目录" aria-label="折叠目录">◂</button>
      </div>
      <div id="toc-list"></div>
    </nav>
    <main id="main">
      <div id="page"><article id="doc" contenteditable="true" spellcheck="false"></article></div>
    </main>
    <script>
      const toc = document.getElementById('toc');
      const tocList = document.getElementById('toc-list');
      const tocToggle = document.getElementById('toc-toggle');
      const main = document.getElementById('main');
      const doc = document.getElementById('doc');
      let tocItems = [];
      let collapsed = false;
      let editTimer = null;
      let applying = false;
      try { collapsed = sessionStorage.getItem('tocCollapsed') === '1'; } catch (e) {}
      applyCollapsed();
      tocToggle.addEventListener('click', function () {
        collapsed = !collapsed;
        applyCollapsed();
        try { sessionStorage.setItem('tocCollapsed', collapsed ? '1' : '0'); } catch (e) {}
      });
      function applyCollapsed() {
        document.body.classList.toggle('toc-collapsed', collapsed);
        tocToggle.textContent = collapsed ? '▸' : '◂';
        tocToggle.title = collapsed ? '展开目录' : '折叠目录';
        tocToggle.setAttribute('aria-label', tocToggle.title);
      }
      function scrollParent() {
        return document.body.classList.contains('has-toc') ? main : window;
      }
      function scrollTop() {
        const root = scrollParent();
        return root === window ? window.scrollY : root.scrollTop;
      }
      function buildToc(root) {
        // 还没输入文字的空标题只显示占位，不进目录。
        const headings = Array.from(root.querySelectorAll('h1,h2,h3,h4,h5,h6'))
          .filter(function (heading) { return !isVisuallyEmpty(heading); });
        tocList.innerHTML = '';
        tocItems = [];
        if (headings.length === 0) {
          toc.hidden = true;
          document.body.classList.remove('has-toc');
          return;
        }
        toc.hidden = false;
        document.body.classList.add('has-toc');
        headings.forEach(function (heading, index) {
          const id = 'heading-' + index;
          heading.id = id;
          const button = document.createElement('button');
          button.type = 'button';
          button.className = 'toc-item toc-h' + heading.tagName.charAt(1);
          button.textContent = (heading.textContent || '').trim();
          button.title = button.textContent;
          button.addEventListener('mousedown', function (event) { event.preventDefault(); });
          button.addEventListener('click', function () {
            window.__syncing = true;
            heading.scrollIntoView({ behavior: 'smooth', block: 'start' });
            setActiveToc(index);
            const line = parseInt(heading.getAttribute('data-line') || '1', 10);
            window.webkit.messageHandlers.previewScroll.postMessage(line);
            setTimeout(function () { window.__syncing = false; }, 120);
          });
          tocList.appendChild(button);
          tocItems.push({ heading: heading, button: button });
        });
        updateActiveToc();
      }
      function setActiveToc(index) {
        tocItems.forEach(function (item, i) {
          item.button.classList.toggle('active', i === index);
        });
      }
      function updateActiveToc() {
        if (!tocItems.length) return;
        const y = 24;
        let active = 0;
        for (let i = 0; i < tocItems.length; i++) {
          if (tocItems[i].heading.getBoundingClientRect().top <= y + 8) active = i;
          else break;
        }
        setActiveToc(active);
      }
      function serializeInline(node) {
        let out = '';
        node.childNodes.forEach(function (child) {
          if (child.nodeType === Node.TEXT_NODE) {
            out += child.textContent;
            return;
          }
          if (child.nodeType !== Node.ELEMENT_NODE) return;
          const tag = child.tagName.toLowerCase();
          if (tag === 'br') out += '\\n';
          else if (tag === 'strong' || tag === 'b') out += '**' + serializeInline(child) + '**';
          else if (tag === 'em' || tag === 'i') out += '*' + serializeInline(child) + '*';
          else if (tag === 'code') out += '`' + child.textContent + '`';
          else if (tag === 'a') out += '[' + serializeInline(child) + '](' + (child.getAttribute('href') || '') + ')';
          else if (tag === 'img') out += '![' + (child.getAttribute('alt') || '') + '](' + (child.getAttribute('src') || '') + ')';
          else out += serializeInline(child);
        });
        return out;
      }
      function serializeTable(table) {
        const rows = Array.from(table.querySelectorAll('tr')).map(function (tr) {
          return Array.from(tr.children).map(function (cell) {
            return serializeInline(cell).trim();
          });
        }).filter(function (row) { return row.length > 0; });
        if (!rows.length) return '';
        const header = rows[0];
        const sep = header.map(function () { return '---'; });
        const body = rows.slice(1);
        return [header, sep].concat(body).map(function (row) {
          return '| ' + row.join(' | ') + ' |';
        }).join('\\n');
      }
      function serializeBlock(node) {
        if (node.nodeType === Node.TEXT_NODE) {
          const text = node.textContent.replace(/\\s+/g, ' ').trim();
          return text || null;
        }
        if (node.nodeType !== Node.ELEMENT_NODE) return null;
        const tag = node.tagName.toLowerCase();
        if (tag === 'h1' || tag === 'h2' || tag === 'h3' || tag === 'h4' || tag === 'h5' || tag === 'h6') {
          return '#'.repeat(Number(tag.charAt(1))) + ' ' + serializeInline(node).trim();
        }
        if (tag === 'p' || tag === 'div') {
          const text = serializeInline(node).replace(/\\n{3,}/g, '\\n\\n').trim();
          return text || null;
        }
        if (tag === 'pre') {
          const code = node.querySelector('code');
          const text = (code ? code.textContent : node.textContent).replace(/\\n$/, '');
          let lang = '';
          if (code && code.className) {
            const match = code.className.match(/language-([\\w+-]+)/);
            if (match) lang = match[1];
          }
          return '```' + lang + '\\n' + text + '\\n```';
        }
        if (tag === 'blockquote') {
          const inner = serializeBlocks(node).split('\\n');
          return inner.map(function (line) { return '> ' + line; }).join('\\n');
        }
        if (tag === 'ul') {
          return Array.from(node.children).filter(function (child) {
            return child.tagName && child.tagName.toLowerCase() === 'li';
          }).map(function (li) {
            return '- ' + serializeInline(li).trim();
          }).join('\\n');
        }
        if (tag === 'ol') {
          return Array.from(node.children).filter(function (child) {
            return child.tagName && child.tagName.toLowerCase() === 'li';
          }).map(function (li, index) {
            return (index + 1) + '. ' + serializeInline(li).trim();
          }).join('\\n');
        }
        if (tag === 'hr') return '---';
        if (tag === 'table') return serializeTable(node);
        return serializeInline(node).trim() || null;
      }
      function serializeBlocks(root) {
        const parts = [];
        root.childNodes.forEach(function (node) {
          const chunk = serializeBlock(node);
          if (chunk) parts.push(chunk);
        });
        return parts.join('\\n\\n').replace(/\\n{3,}/g, '\\n\\n').trim();
      }
      function flushEdit() {
        if (applying) return;
        const markdown = serializeBlocks(doc);
        window.webkit.messageHandlers.previewEdit.postMessage(markdown ? markdown + '\\n' : '');
      }
      function scheduleEdit() {
        clearTimeout(editTimer);
        editTimer = setTimeout(flushEdit, 180);
      }
      function isVisuallyEmpty(node) {
        if (!node) return true;
        const text = (node.textContent || '').replace(/\\u00a0/g, ' ').trim();
        if (text.length > 0) return false;
        const meaningful = node.querySelector('img, table, pre, hr, video, iframe');
        return !meaningful;
      }
      function syncEmptyMarks(root) {
        const focused = currentBlock();
        const nodes = root.querySelectorAll('h1,h2,h3,h4,h5,h6,p,li,blockquote');
        nodes.forEach(function (node) {
          let empty = isVisuallyEmpty(node);
          if (empty && node.tagName.toLowerCase() === 'p') {
            // 正文占位只在当前段落或整篇只有这一段时显示，避免满屏「输入正文」。
            empty = node === focused || root.children.length === 1;
          }
          node.classList.toggle('is-empty', empty);
        });
      }
      function render(html, theme) {
        applying = true;
        document.documentElement.dataset.theme = theme;
        const selection = saveSelection();
        doc.innerHTML = html || '<p><br></p>';
        syncEmptyMarks(doc);
        buildToc(doc);
        restoreSelection(selection);
        applying = false;
      }
      function saveSelection() {
        const selection = window.getSelection();
        if (!selection || selection.rangeCount === 0) return null;
        const range = selection.getRangeAt(0);
        if (!doc.contains(range.startContainer)) return null;
        return {
          start: pathForNode(range.startContainer, range.startOffset),
          end: pathForNode(range.endContainer, range.endOffset)
        };
      }
      function pathForNode(node, offset) {
        const path = [];
        let current = node;
        while (current && current !== doc) {
          const parent = current.parentNode;
          if (!parent) break;
          path.push(Array.prototype.indexOf.call(parent.childNodes, current));
          current = parent;
        }
        return { path: path.reverse(), offset: offset };
      }
      function nodeForPath(info) {
        let node = doc;
        for (let i = 0; i < info.path.length; i++) {
          node = node.childNodes[info.path[i]];
          if (!node) return null;
        }
        return node;
      }
      function restoreSelection(info) {
        if (!info) return;
        const startNode = nodeForPath(info.start);
        const endNode = nodeForPath(info.end);
        if (!startNode || !endNode) return;
        const selection = window.getSelection();
        const range = document.createRange();
        try {
          range.setStart(startNode, Math.min(info.start.offset, startNode.nodeType === 3 ? startNode.length : startNode.childNodes.length));
          range.setEnd(endNode, Math.min(info.end.offset, endNode.nodeType === 3 ? endNode.length : endNode.childNodes.length));
          selection.removeAllRanges();
          selection.addRange(range);
        } catch (e) {}
      }
      function scrollToLine(line) {
        window.__syncing = true;
        const nodes = document.querySelectorAll('[data-line]');
        let target = null;
        for (const node of nodes) {
          const n = parseInt(node.getAttribute('data-line'), 10);
          if (n <= line) target = node;
          else break;
        }
        if (target) {
          const root = scrollParent();
          if (root === window) {
            const top = target.getBoundingClientRect().top + window.scrollY - 12;
            window.scrollTo(0, Math.max(0, top));
          } else {
            const top = target.getBoundingClientRect().top - main.getBoundingClientRect().top + main.scrollTop - 12;
            main.scrollTo(0, Math.max(0, top));
          }
        }
        updateActiveToc();
        setTimeout(function () { window.__syncing = false; }, 80);
      }
      function currentBlock() {
        const selection = window.getSelection();
        if (!selection || selection.rangeCount === 0) return null;
        let node = selection.anchorNode;
        if (!node) return null;
        if (node.nodeType === Node.TEXT_NODE) node = node.parentElement;
        while (node && node !== doc) {
          if (node.nodeType === Node.ELEMENT_NODE) {
            const tag = node.tagName.toLowerCase();
            if (tag === 'p' || tag === 'div' || tag === 'h1' || tag === 'h2' || tag === 'h3' || tag === 'h4' || tag === 'h5' || tag === 'h6' || tag === 'li' || tag === 'blockquote' || tag === 'pre') {
              return node;
            }
          }
          node = node.parentElement;
        }
        return null;
      }
      function textBeforeCaret(block) {
        const selection = window.getSelection();
        if (!selection || selection.rangeCount === 0) return '';
        const range = selection.getRangeAt(0).cloneRange();
        range.selectNodeContents(block);
        range.setEnd(selection.anchorNode, selection.anchorOffset);
        return range.toString();
      }
      function placeCaretStart(node) {
        const selection = window.getSelection();
        const range = document.createRange();
        if (node.childNodes.length === 0) node.appendChild(document.createElement('br'));
        range.setStart(node, 0);
        range.collapse(true);
        selection.removeAllRanges();
        selection.addRange(range);
      }
      function deleteFromBlockStartToCaret(block) {
        const selection = window.getSelection();
        if (!selection || selection.rangeCount === 0) return false;
        const range = document.createRange();
        range.selectNodeContents(block);
        range.setEnd(selection.anchorNode, selection.anchorOffset);
        if (!range.toString().length) return false;
        range.deleteContents();
        return true;
      }
      function deleteCharsBeforeCaret(count) {
        const selection = window.getSelection();
        if (!selection || selection.rangeCount === 0 || !selection.isCollapsed || count <= 0) return false;
        selection.collapse(selection.anchorNode, selection.anchorOffset);
        for (let i = 0; i < count; i++) {
          selection.modify('extend', 'backward', 'character');
        }
        const selected = selection.toString();
        if (!selected.length) return false;
        document.execCommand('delete');
        return true;
      }
      function moveChildren(from, to) {
        while (from.firstChild) to.appendChild(from.firstChild);
        if (!to.textContent) to.appendChild(document.createElement('br'));
      }
      function convertBlock(block, tagName) {
        if (!deleteFromBlockStartToCaret(block)) return false;
        const next = document.createElement(tagName);
        moveChildren(block, next);
        block.replaceWith(next);
        placeCaretStart(next);
        return true;
      }
      function convertToList(block, ordered) {
        if (!deleteFromBlockStartToCaret(block)) return false;
        const list = document.createElement(ordered ? 'ol' : 'ul');
        const item = document.createElement('li');
        moveChildren(block, item);
        list.appendChild(item);
        block.replaceWith(list);
        placeCaretStart(item);
        return true;
      }
      function convertToQuote(block) {
        if (!deleteFromBlockStartToCaret(block)) return false;
        const quote = document.createElement('blockquote');
        const paragraph = document.createElement('p');
        moveChildren(block, paragraph);
        quote.appendChild(paragraph);
        block.replaceWith(quote);
        placeCaretStart(paragraph);
        return true;
      }
      function tryBlockShortcut() {
        const block = currentBlock();
        if (!block) return false;
        const tag = block.tagName.toLowerCase();
        if (tag === 'pre' || tag === 'li') return false;
        const before = textBeforeCaret(block);
        if (/^#{1,6}$/.test(before)) return convertBlock(block, 'h' + before.length);
        if (before === '-' || before === '*' || before === '+') return convertToList(block, false);
        if (/^\\d+\\.$/.test(before)) return convertToList(block, true);
        if (before === '>') return convertToQuote(block);
        return false;
      }
      function isEmptyBlock(node) {
        if (!node) return true;
        const text = (node.textContent || '').replace(/\\u00a0/g, ' ').trim();
        return text.length === 0;
      }
      function breakOutOfStyledBlock(block) {
        const tag = block.tagName.toLowerCase();
        if (tag === 'li') {
          const list = block.parentElement;
          const paragraph = document.createElement('p');
          paragraph.appendChild(document.createElement('br'));
          if (list && (list.tagName.toLowerCase() === 'ul' || list.tagName.toLowerCase() === 'ol')) {
            if (list.childNodes.length === 1) {
              list.replaceWith(paragraph);
            } else {
              list.after(paragraph);
              block.remove();
              if (!list.childNodes.length) list.remove();
            }
          } else {
            block.replaceWith(paragraph);
          }
          placeCaretStart(paragraph);
          return true;
        }
        if (tag === 'h1' || tag === 'h2' || tag === 'h3' || tag === 'h4' || tag === 'h5' || tag === 'h6' || tag === 'blockquote') {
          const paragraph = document.createElement('p');
          paragraph.appendChild(document.createElement('br'));
          block.after(paragraph);
          if (isEmptyBlock(block)) block.remove();
          placeCaretStart(paragraph);
          return true;
        }
        return false;
      }
      function tryInlineMarkers() {
        const selection = window.getSelection();
        if (!selection || selection.rangeCount === 0 || !selection.isCollapsed) return false;
        const block = currentBlock();
        if (!block || block.tagName.toLowerCase() === 'pre') return false;
        const before = textBeforeCaret(block);
        let full = '';
        let inner = '';
        let wrap = '';
        let match = before.match(/\\*\\*([^*]+)\\*\\*$/);
        if (match) { full = match[0]; inner = match[1]; wrap = 'strong'; }
        if (!wrap) {
          match = before.match(/__([^_]+)__$/);
          if (match) { full = match[0]; inner = match[1]; wrap = 'strong'; }
        }
        if (!wrap) {
          match = before.match(/`([^`]+)`$/);
          if (match) { full = match[0]; inner = match[1]; wrap = 'code'; }
        }
        if (!wrap) {
          match = before.match(/(^|[^*])\\*([^*]+)\\*$/);
          if (match && match[0].slice(-2) !== '**') {
            full = match[0].slice(match[1].length);
            inner = match[2];
            wrap = 'em';
          }
        }
        if (!wrap) {
          match = before.match(/(^|[^_])_([^_]+)_$/);
          if (match && match[0].slice(-2) !== '__') {
            full = match[0].slice(match[1].length);
            inner = match[2];
            wrap = 'em';
          }
        }
        if (!wrap || !full) return false;
        if (!deleteCharsBeforeCaret(full.length)) return false;
        const mark = document.createElement(wrap);
        mark.textContent = inner;
        const sel = window.getSelection();
        const range = sel.getRangeAt(0);
        range.insertNode(mark);
        const after = document.createRange();
        after.setStartAfter(mark);
        after.collapse(true);
        sel.removeAllRanges();
        sel.addRange(after);
        return true;
      }
      doc.addEventListener('input', function () {
        if (applying) return;
        syncEmptyMarks(doc);
        buildToc(doc);
        scheduleEdit();
      });
      doc.addEventListener('keyup', function () {
        if (applying) return;
        syncEmptyMarks(doc);
      });
      doc.addEventListener('blur', function () {
        clearTimeout(editTimer);
        flushEdit();
      });
      doc.addEventListener('click', function (event) {
        const link = event.target.closest('a');
        if (!link) return;
        if (event.metaKey || event.ctrlKey) return;
        event.preventDefault();
      });
      doc.addEventListener('keydown', function (event) {
        if ((event.metaKey || event.ctrlKey) && (event.key === 's' || event.key === 'S')) {
          event.preventDefault();
          clearTimeout(editTimer);
          flushEdit();
          window.webkit.messageHandlers.previewSave.postMessage(null);
          return;
        }
        if (event.isComposing || event.keyCode === 229) return;
        if (event.key === ' ' || event.code === 'Space') {
          if (tryBlockShortcut()) {
            event.preventDefault();
            syncEmptyMarks(doc);
            buildToc(doc);
            scheduleEdit();
            return;
          }
        }
        if (event.key === 'Enter' && !event.shiftKey) {
          const block = currentBlock();
          if (block && isEmptyBlock(block) && breakOutOfStyledBlock(block)) {
            event.preventDefault();
            syncEmptyMarks(doc);
            buildToc(doc);
            scheduleEdit();
            return;
          }
        }
        if (event.key === '`' || event.key === '*' || event.key === '_') {
          setTimeout(function () {
            if (applying) return;
            if (tryInlineMarkers()) {
              syncEmptyMarks(doc);
              buildToc(doc);
              scheduleEdit();
            }
          }, 0);
        }
      });
      let scrollTimer = null;
      function onScroll() {
        if (window.__syncing) return;
        clearTimeout(scrollTimer);
        scrollTimer = setTimeout(function () {
          updateActiveToc();
          const nodes = document.querySelectorAll('[data-line]');
          let line = 1;
          const y = 16;
          for (const node of nodes) {
            if (node.getBoundingClientRect().top <= y) line = parseInt(node.getAttribute('data-line'), 10);
          }
          window.webkit.messageHandlers.previewScroll.postMessage(line);
        }, 40);
      }
      window.addEventListener('scroll', onScroll, { passive: true });
      main.addEventListener('scroll', onScroll, { passive: true });
    </script>
    </body></html>
    """
}
