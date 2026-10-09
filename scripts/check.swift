import Foundation
import EditorCore

func expect(_ condition: Bool, _ message: String) {
    if !condition {
        fputs("失败：\(message)\n", stderr)
        exit(1)
    }
}

let deleted = BookmarkAdjust.adjust([4, 5, 6, 7], changes: [
    LineChange(startLine: 5, endLine: 6, startColumn: 1, endColumn: 1, text: "")
])
expect(deleted == [4, 5, 6], "删除行后书签应跟着剩下的内容")

let inserted = BookmarkAdjust.adjust([1, 3], changes: [
    LineChange(startLine: 1, endLine: 1, startColumn: 1, endColumn: 1, text: "\n")
])
expect(inserted == [2, 4], "在开头插入空行应下移书签")

let typed = BookmarkAdjust.adjust([5], changes: [
    LineChange(startLine: 5, endLine: 5, startColumn: 3, endColumn: 3, text: "a")
])
expect(typed == [5], "同一行输入应保留书签")

let utf8 = try TextCodec.encode("中文\nnext", encoding: .utf8, eol: .lf)
let decodedUTF8 = try TextCodec.read(utf8)
expect(decodedUTF8.text == "中文\nnext" && decodedUTF8.encoding == .utf8 && decodedUTF8.eol == .lf, "UTF-8 往返")

var bom = Data([0xEF, 0xBB, 0xBF])
bom.append(Data("你好".utf8))
let decodedBOM = try TextCodec.read(bom)
expect(decodedBOM.text == "你好" && decodedBOM.encoding == .utf8, "UTF-8 BOM 不应出现在正文里")

let gbk = try TextCodec.encode("中文编辑器", encoding: .gbk, eol: .lf)
let decodedGBK = try TextCodec.decode(gbk, as: .gbk)
expect(decodedGBK.text == "中文编辑器", "GBK 往返")
let detected = try TextCodec.read(gbk)
expect(detected.text == "中文编辑器" && (detected.encoding == .gbk || detected.encoding == .gb2312), "GBK 自动判断")

let crlf = try TextCodec.encode("a\nb", encoding: .utf8, eol: .crlf)
expect(String(data: crlf, encoding: .utf8) == "a\r\nb", "保存时写回 CRLF")

let html = MarkdownHTML.render("""
# 标题

**粗** 和 `code`

- 一项
- 两项

> 引用

| 名 | 值 |
| --- | --- |
| A | 1 |
""")
expect(html.contains("<h1 data-line=\"1\">标题</h1>"), "标题")
expect(html.contains("<strong>粗</strong>"), "粗体")
expect(html.contains("<code>code</code>"), "行内代码")
expect(html.contains("<li data-line=\"5\">一项</li>"), "列表")
expect(html.contains("<blockquote data-line=\"8\">"), "引用")
expect(html.contains("<th>名</th>") && html.contains("<td>1</td>"), "表格")

let breaks = MarkdownHTML.render("第一行\n第二行\n\n第三行")
expect(breaks.contains("第一行<br>第二行"), "同一段里的换行要在预览里断开")
expect(breaks.contains("<p data-line=\"4\">第三行</p>"), "空行仍然另起一段")

let fenced = MarkdownHTML.render("""
```html
<b>不是标签</b>
```
""")
expect(fenced.contains("&lt;b&gt;") && !fenced.contains("<b>不是标签</b>"), "代码块要转义")

let inline = MarkdownHTML.renderInline("[文档](https://example.com) 和 ![图](pic.png)")
expect(inline.contains(#"<a href="https://example.com">文档</a>"#), "链接")
expect(inline.contains(#"<img alt="图" src="pic.png">"#), "图片")

expect(Language.from(url: URL(fileURLWithPath: "Demo.cs")) == .csharp, "cs 识别为 C#")

let csharp = "public class Demo {\n    int n = 1; // 注释\n    string s = \"a{b}\";\n}\n"
let csharpSpans = Syntax.spans(in: csharp, language: .csharp)
func piece(_ span: SyntaxSpan, _ source: String) -> String {
    let ns = source as NSString
    return ns.substring(with: NSRange(location: span.location, length: span.length))
}
let named = "public class TestJob : JobBase {\n    public Task Execute(string args) {\n        return GetFullName();\n    }\n}\n"
let namedSpans = Syntax.spans(in: named, language: .csharp)
let namespace = "namespace RekTec.Xrm.Jobs\nusing System.Collections;\n"
let namespaceSpans = Syntax.spans(in: namespace, language: .csharp)
expect(namespaceSpans.contains { $0.kind == .namespace && piece($0, namespace) == "RekTec" }, "命名空间名")
expect(namespaceSpans.contains { $0.kind == .namespace && piece($0, namespace) == "Jobs" }, "点号后面的命名空间")
expect(namespaceSpans.contains { $0.kind == .namespace && piece($0, namespace) == "Collections" }, "using 里的命名空间")

expect(namedSpans.contains { $0.kind == .type && piece($0, named) == "TestJob" }, "类名")
expect(namedSpans.contains { $0.kind == .type && piece($0, named) == "JobBase" }, "基类名")
expect(namedSpans.contains { $0.kind == .function && piece($0, named) == "Execute" }, "函数名")
expect(namedSpans.contains { $0.kind == .function && piece($0, named) == "GetFullName" }, "调用的函数名")

let python = "class Demo:\n    def run(self):\n        self.work()\n"
let pythonSpans = Syntax.spans(in: python, language: .python)
expect(pythonSpans.contains { $0.kind == .type && piece($0, python) == "Demo" }, "Python 类名")
expect(pythonSpans.contains { $0.kind == .function && piece($0, python) == "run" }, "Python 函数名")
expect(pythonSpans.contains { $0.kind == .function && piece($0, python) == "work" }, "Python 方法调用")

expect(csharpSpans.contains { $0.kind == .keyword && piece($0, csharp) == "public" }, "C# 关键字")
expect(csharpSpans.contains { $0.kind == .type && piece($0, csharp) == "int" }, "C# 类型")
expect(csharpSpans.contains { $0.kind == .comment }, "C# 注释")
expect(csharpSpans.contains { $0.kind == .string && piece($0, csharp).contains("{") }, "C# 字符串")

let open = (csharp as NSString).range(of: "{").location
let pair = Syntax.bracePair(in: csharp, language: .csharp, caret: open + 1)
expect(pair?.0 == open, "光标在左括号旁能配上")
expect(pair != nil && (csharp as NSString).character(at: pair!.1) == 125, "配到类结尾的右括号")

let inside = (csharp as NSString).range(of: "{b}").location + 1
expect(Syntax.bracePair(in: csharp, language: .csharp, caret: inside) == nil, "字符串里的括号不配对")

let nested = "f(a[1]);"
let paren = (nested as NSString).range(of: "(").location
let nestedPair = Syntax.bracePair(in: nested, language: .javascript, caret: paren + 1)
expect(nestedPair?.1 == (nested as NSString).range(of: ")").location, "嵌套括号配最外层")

let sql = Syntax.spans(in: "SELECT id FROM t; -- 备注", language: .sql)
expect(sql.contains { $0.kind == .keyword && piece($0, "SELECT id FROM t; -- 备注") == "SELECT" }, "SQL 不区分大小写")
expect(sql.contains { $0.kind == .comment }, "SQL 注释")

let jsonSource = "{\n  \"name\": \"value\",\n  \"n\": 1\n}\n"
let json = Syntax.spans(in: jsonSource, language: .json)
expect(json.contains { $0.kind == .key && piece($0, jsonSource) == "\"name\"" }, "JSON 键")
expect(json.contains { $0.kind == .string && piece($0, jsonSource) == "\"value\"" }, "JSON 字符串值")
expect(json.contains { $0.kind == .number && piece($0, jsonSource) == "1" }, "JSON 数字")
let jsonOpen = (jsonSource as NSString).range(of: "{").location
expect(Syntax.bracePair(in: jsonSource, language: .json, caret: jsonOpen + 1) != nil, "JSON 括号匹配")
let hidden = "{\"b\": \"}\"}"
let hiddenAt = (hidden as NSString).range(of: "\"}\"").location + 2
expect(Syntax.bracePair(in: hidden, language: .json, caret: hiddenAt) == nil, "JSON 字符串里的括号不匹配")

let htmlSource = "<div class=\"a\">"
let htmlSpans = Syntax.spans(in: htmlSource, language: .html)
expect(htmlSpans.contains { $0.kind == .keyword && piece($0, htmlSource) == "div" }, "HTML 标签")

let cssSource = "@media screen { font-size: 12px; } /* 备注 */"
let css = Syntax.spans(in: cssSource, language: .css)
expect(css.contains { $0.kind == .keyword && piece($0, cssSource) == "@media" }, "CSS @规则")
expect(css.contains { $0.kind == .keyword && piece($0, cssSource) == "font-size" }, "CSS 属性")
expect(css.contains { $0.kind == .comment }, "CSS 注释")
let cssBrace = (cssSource as NSString).range(of: "{").location
expect(Syntax.bracePair(in: cssSource, language: .css, caret: cssBrace + 1) != nil, "CSS 括号")

let jsSource = "const n = undefined;\nfunction run() {}"
let js = Syntax.spans(in: jsSource, language: .javascript)
expect(js.contains { $0.kind == .keyword && piece($0, jsSource) == "const" }, "JavaScript 关键字")
expect(js.contains { $0.kind == .value && piece($0, jsSource) == "undefined" }, "JavaScript 值")
expect(js.contains { $0.kind == .function && piece($0, jsSource) == "run" }, "JavaScript 函数")

let tsSource = "interface User { name: string }"
let ts = Syntax.spans(in: tsSource, language: .typescript)
expect(ts.contains { $0.kind == .keyword && piece($0, tsSource) == "interface" }, "TypeScript 关键字")
expect(ts.contains { $0.kind == .type && piece($0, tsSource) == "string" }, "TypeScript 类型")

let yamlSource = "ok: true # 备注"
let yaml = Syntax.spans(in: yamlSource, language: .yaml)
expect(yaml.contains { $0.kind == .key && piece($0, yamlSource) == "ok" }, "YAML 键")
expect(yaml.contains { $0.kind == .value && piece($0, yamlSource) == "true" }, "YAML 值")
expect(yaml.contains { $0.kind == .comment }, "YAML 注释")
let compose = "version: '3'\nimage: nrm.example.com:44382/app:6.23.0\nrestart: always\nmemory: 2048m\ncount: 2\n- TZ=Asia/Shanghai\n"
let composeSpans = Syntax.spans(in: compose, language: .yaml)
expect(composeSpans.contains { $0.kind == .key && piece($0, compose) == "version" }, "YAML 键 version")
expect(composeSpans.contains { $0.kind == .string && piece($0, compose) == "'3'" }, "YAML 引号字符串")
expect(composeSpans.contains { $0.kind == .string && piece($0, compose) == "nrm.example.com:44382/app:6.23.0" }, "YAML 地址整段是字符串")
expect(composeSpans.contains { $0.kind == .string && piece($0, compose) == "always" }, "YAML 普通值")
expect(composeSpans.contains { $0.kind == .string && piece($0, compose) == "2048m" }, "YAML 带单位的值")
expect(composeSpans.contains { $0.kind == .number && piece($0, compose) == "2" }, "YAML 数字")
expect(composeSpans.contains { $0.kind == .string && piece($0, compose) == "TZ=Asia/Shanghai" }, "YAML 列表项")
expect(!composeSpans.contains { $0.kind == .type }, "YAML 不把冒号后面当成类型")

let shellSource = "echo hi # 备注"
let shell = Syntax.spans(in: shellSource, language: .shell)
expect(shell.contains { $0.kind == .keyword && piece($0, shellSource) == "echo" }, "Shell 关键字")
expect(shell.contains { $0.kind == .comment }, "Shell 注释")

let javaSource = "public class Demo { void run() {} }"
let java = Syntax.spans(in: javaSource, language: .java)
expect(java.contains { $0.kind == .type && piece($0, javaSource) == "Demo" }, "Java 类名")
expect(java.contains { $0.kind == .function && piece($0, javaSource) == "run" }, "Java 方法")
expect(java.contains { $0.kind == .type && piece($0, javaSource) == "void" }, "Java 类型")

let cppSource = "#include <stdio.h>\nint main() { return 0; }"
let cpp = Syntax.spans(in: cppSource, language: .cpp)
expect(cpp.contains { $0.kind == .keyword && piece($0, cppSource) == "#include" }, "C++ 预处理")
expect(cpp.contains { $0.kind == .type && piece($0, cppSource) == "int" }, "C++ 类型")
expect(cpp.contains { $0.kind == .function && piece($0, cppSource) == "main" }, "C++ 函数")

let xmlSource = "<note id=\"1\"/>"
let xml = Syntax.spans(in: xmlSource, language: .xml)
expect(xml.contains { $0.kind == .keyword && piece($0, xmlSource) == "note" }, "XML 标签")

print("check ok")
