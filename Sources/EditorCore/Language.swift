import Foundation

public enum Language: String, CaseIterable, Codable, Sendable {
    case plaintext
    case markdown
    case json
    case html
    case css
    case javascript
    case typescript
    case python
    case xml
    case sql
    case shell
    case yaml
    case cpp
    case csharp
    case java

    public var label: String {
        switch self {
        case .plaintext: return "纯文本"
        case .markdown: return "Markdown"
        case .json: return "JSON"
        case .html: return "HTML"
        case .css: return "CSS"
        case .javascript: return "JavaScript"
        case .typescript: return "TypeScript"
        case .python: return "Python"
        case .xml: return "XML"
        case .sql: return "SQL"
        case .shell: return "Shell"
        case .yaml: return "YAML"
        case .cpp: return "C/C++"
        case .csharp: return "C#"
        case .java: return "Java"
        }
    }

    public static func from(url: URL) -> Language {
        switch url.pathExtension.lowercased() {
        case "txt": return .plaintext
        case "md", "markdown": return .markdown
        case "json": return .json
        case "html", "htm": return .html
        case "css": return .css
        case "js", "mjs", "cjs": return .javascript
        case "ts", "tsx": return .typescript
        case "py": return .python
        case "xml": return .xml
        case "sql": return .sql
        case "sh", "bash", "zsh": return .shell
        case "yml", "yaml": return .yaml
        case "c", "h", "cpp", "hpp", "cc": return .cpp
        case "cs": return .csharp
        case "java": return .java
        default: return .plaintext
        }
    }
}

public enum AppTheme: String, Codable, Sendable {
    case light
    case dark
}

public enum LineEnding: String, Codable, Sendable {
    case lf = "LF"
    case crlf = "CRLF"
}
