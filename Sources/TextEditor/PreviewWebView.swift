import AppKit
import EditorCore
import WebKit

final class PreviewController: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    var onScrollLine: ((Int) -> Void)?
    private let bridge = ScriptBridge()
    private var body = ""
    private var theme = AppTheme.light
    private var basePath = ""
    private var ready = false
    private var anchorLine = 1
    private var ignoringPreviewScroll = false

    override init() {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        config.userContentController = controller
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        bridge.owner = self
        controller.add(bridge, name: "previewScroll")
        webView.navigationDelegate = self
    }

    func update(body: String, theme: AppTheme, baseURL: URL?, anchorLine: Int) {
        let path = baseURL?.absoluteString ?? ""
        let baseChanged = path != basePath
        self.body = body
        self.theme = theme
        self.basePath = path
        self.anchorLine = max(1, anchorLine)
        if baseChanged || !ready {
            ready = false
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
        guard message.name == "previewScroll" else { return }
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
      :root { color-scheme: light; --bg: #f7f5f0; --fg: #2c2a26; --muted: #6d675e; --line: #e4dfd4; --code: rgba(80,60,20,0.08); --link: #2f6a45; }
      :root[data-theme="dark"] { color-scheme: dark; --bg: #1d1c1a; --fg: #ece7df; --muted: #b2ab9f; --line: #3a372f; --code: rgba(255,255,255,0.08); --link: #8fbf9f; }
      html, body { margin: 0; background: var(--bg); color: var(--fg); }
      body { font: 16px/1.65 -apple-system, "PingFang SC", "Hiragino Sans GB", sans-serif; }
      article { box-sizing: border-box; width: 100%; padding: 20px 28px 64px; }
      h1, h2, h3, h4, p, li, blockquote { overflow-wrap: break-word; }
      h1, h2, h3, h4 { line-height: 1.35; margin: 1.1em 0 0.45em; }
      p, ul, ol, pre, table, blockquote { margin: 0.7em 0; }
      a { color: var(--link); }
      code { font-family: ui-monospace, Menlo, monospace; font-size: 0.9em; background: var(--code); padding: 0.1em 0.35em; border-radius: 4px; }
      pre { background: var(--code); padding: 12px 14px; border-radius: 8px; overflow: auto; }
      pre code { background: none; padding: 0; }
      blockquote { margin-left: 0; padding-left: 14px; border-left: 3px solid var(--line); color: var(--muted); }
      table { border-collapse: collapse; width: 100%; }
      th, td { border: 1px solid var(--line); padding: 6px 8px; text-align: left; }
      img { max-width: 100%; }
      hr { border: 0; border-top: 1px solid var(--line); margin: 1.4em 0; }
    </style>
    </head>
    <body><article id="doc"></article>
    <script>
      function render(html, theme) {
        document.documentElement.dataset.theme = theme;
        document.getElementById('doc').innerHTML = html;
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
          const top = target.getBoundingClientRect().top + window.scrollY - 12;
          window.scrollTo(0, Math.max(0, top));
        }
        setTimeout(function () { window.__syncing = false; }, 80);
      }
      let scrollTimer = null;
      window.addEventListener('scroll', function () {
        if (window.__syncing) return;
        clearTimeout(scrollTimer);
        scrollTimer = setTimeout(function () {
          const nodes = document.querySelectorAll('[data-line]');
          let line = 1;
          const y = window.scrollY + 16;
          for (const node of nodes) {
            if (node.offsetTop <= y) line = parseInt(node.getAttribute('data-line'), 10);
          }
          window.webkit.messageHandlers.previewScroll.postMessage(line);
        }, 40);
      });
    </script>
    </body></html>
    """
}
