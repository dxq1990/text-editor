import EditorCore
import Foundation

struct WorkspaceFile: Codable {
    var name: String
    var path: String?
    var text: String
    var encoding: String
    var eol: String
    var language: String
    var dirty: Bool
    var bookmarks: [Int]
    var showPreview: Bool?
}

struct WorkspaceSnapshot: Codable {
    var files: [WorkspaceFile]
    var active: Int
}

enum WorkspaceStore {
    static func fileURL() -> URL {
        SessionStore.fileURL().deletingLastPathComponent().appendingPathComponent("workspace.json")
    }

    static func load() -> WorkspaceSnapshot? {
        guard let data = try? Data(contentsOf: fileURL()) else { return nil }
        return try? JSONDecoder().decode(WorkspaceSnapshot.self, from: data)
    }

    static func save(_ snapshot: WorkspaceSnapshot) {
        let url = fileURL()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
