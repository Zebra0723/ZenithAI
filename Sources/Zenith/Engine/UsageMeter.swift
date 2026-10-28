import Foundation
import ZenithCore

/// Measures Claude Code's usage on this Mac from its own transcripts
/// (~/.claude/projects/*/*.jsonl): Zenith's sandbox runs and anything else using the plan
/// here. Files are re-read only when they change, and only the last two weeks count.
actor UsageMeter {
    static let shared = UsageMeter()

    private struct FileState {
        var size: Int
        var modified: Date
        var entries: [TranscriptUsage.Entry]
    }

    private var files: [String: FileState] = [:]
    private var lastScan = Date.distantPast

    private var root: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects", isDirectory: true)
    }

    /// Re-reads changed transcripts. Cheap when nothing changed.
    func scan(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastScan) > 60 else { return }
        lastScan = Date()
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-15 * 86_400)
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: keys) else { return }
        var present = Set<String>()
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let modified = values.contentModificationDate, modified >= cutoff else { continue }
            let size = values.fileSize ?? 0
            present.insert(url.path)
            if let known = files[url.path], known.size == size, known.modified == modified { continue }
            files[url.path] = FileState(size: size, modified: modified, entries: read(url, since: cutoff))
        }
        files = files.filter { present.contains($0.key) }
    }

    private func read(_ url: URL, since cutoff: Date) -> [TranscriptUsage.Entry] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let text = String(data: data, encoding: .utf8) else { return [] }
        var entries: [TranscriptUsage.Entry] = []
        text.enumerateLines { line, _ in
            if let e = TranscriptUsage.parse(line: line), e.at >= cutoff { entries.append(e) }
        }
        return entries
    }

    /// Usage units since a date, each model message counted once across every file.
    func units(since: Date) -> Double {
        var seen = Set<String>()
        var total = 0.0
        for state in files.values {
            for e in state.entries where e.at >= since && seen.insert(e.key).inserted {
                total += UsageMath.units(e.counts, e.model)
            }
        }
        return total
    }

    /// Every entry since a date, for the governor to sum at any point in the week.
    func entries(since: Date) -> [TranscriptUsage.Entry] {
        var seen = Set<String>()
        return files.values.flatMap(\.entries).filter { $0.at >= since && seen.insert($0.key).inserted }
    }
}
