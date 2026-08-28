import Foundation

struct CodexThreadTitleReader: Sendable {
    func fetchTitles() async -> [String: String] {
        await Task.detached(priority: .utility) {
            let database = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/state_5.sqlite")
            guard FileManager.default.fileExists(atPath: database.path),
                  FileManager.default.isExecutableFile(atPath: "/usr/bin/sqlite3")
            else { return [:] }

            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
            process.arguments = [
                "-json",
                database.path,
                "SELECT id, COALESCE(NULLIF(name, ''), title) AS display_title FROM threads WHERE archived = 0;"
            ]
            process.standardOutput = output
            process.standardError = Pipe()

            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0,
                      let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
                else { return [:] }
                return Dictionary(uniqueKeysWithValues: rows.compactMap { row -> (String, String)? in
                    guard let id = row["id"] as? String,
                          let title = row["display_title"] as? String,
                          !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    else { return nil }
                    return (id, title)
                })
            } catch {
                return [:]
            }
        }.value
    }
}
