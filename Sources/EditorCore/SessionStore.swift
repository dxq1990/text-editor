import Foundation

public struct SessionSettings: Codable, Equatable, Sendable {
    public var theme: AppTheme
    public var wordWrap: Bool
    public var recent: [String]

    public init(theme: AppTheme = .light, wordWrap: Bool = false, recent: [String] = []) {
        self.theme = theme
        self.wordWrap = wordWrap
        self.recent = recent
    }
}

public enum SessionStore {
    public static func fileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("TextEditor/session.json", isDirectory: false)
    }

    public static func load(from url: URL = fileURL()) -> SessionSettings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(SessionSettings.self, from: data) else {
            return SessionSettings()
        }
        return SessionSettings(
            theme: settings.theme,
            wordWrap: settings.wordWrap,
            recent: Array(settings.recent.prefix(10))
        )
    }

    public static func save(_ settings: SessionSettings, to url: URL = fileURL()) {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder.pretty.encode(settings) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
