import Foundation
import ZenithCore

/// One call to Claude Code.
struct ClaudeRequest {
    var prompt: String
    var model: ModelTier
    var directory: URL
    var appendSystemPrompt: String?
    /// nil keeps Claude Code's default tools; [] turns every tool off.
    var tools: [String]?
    /// Resume this session, so a follow-up keeps its context instead of re-reading.
    var resume: String?
    var cloud = false
    var sandboxed = true
}

enum ClaudeError: LocalizedError {
    case notInstalled
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled: return "Claude Code isn't installed, or Zenith can't find it. Set its path in Settings."
        case .cancelled: return "Stopped."
        case .failed(let why): return why
        }
    }
}

/// Runs Claude Code headless (`claude -p`) logged into the user's Max plan, never the paid
/// API: Zenith takes the API key variables out of the environment before every run, so
/// Claude Code uses the subscription login.
final class ClaudeCode: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    static func locate(_ custom: String) -> String? {
        let fm = FileManager.default
        if !custom.isEmpty { return fm.isExecutableFile(atPath: custom) ? custom : nil }
        let home = fm.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude", "\(home)/.bun/bin/claude", "\(home)/.npm-global/bin/claude",
        ]
        if let found = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) { return found }
        // Ask a login shell, which has the user's PATH.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "command -v claude"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let path = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.hasPrefix("/") && fm.isExecutableFile(atPath: path) ? path : nil
    }

    static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // The Max plan, never the paid API.
        for key in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL", "CLAUDE_CODE_USE_BEDROCK",
                    "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY"] {
            env.removeValue(forKey: key)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extra = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.bun/bin"]
        env["PATH"] = (extra + [env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]).joined(separator: ":")
        env["CLAUDE_CODE_ENTRYPOINT"] = "zenith"
        return env
    }

    /// The sandbox profile: the worker may read the Mac (minus mail, messages and the user's
    /// documents) but write only to its workspace, Claude Code's own state, and caches.
    static func sandboxProfile(workspace: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        let claudeState = "^" + NSRegularExpression.escapedPattern(for: home + "/.claude")
        let writable = [workspace.path, "\(home)/Library/Caches", "\(home)/.npm", "\(home)/.bun", "\(home)/.cache",
                        "\(home)/.config", "\(home)/Library/pnpm", "/private/tmp", "/private/var/folders", "/dev"]
        let private_ = ["\(home)/Library/Messages", "\(home)/Library/Mail", "\(home)/Documents", "\(home)/Desktop",
                        "\(home)/Pictures", "\(home)/Library/Application Support/Galaxy"]
        return """
        (version 1)
        (allow default)
        (deny file-write*)
        (allow file-write*
          \(writable.map { "(subpath \(q($0)))" }.joined(separator: "\n  "))
          (regex #"\(claudeState)"))
        (deny file-read*
          \(private_.map { "(subpath \(q($0)))" }.joined(separator: "\n  ")))
        """
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let p = process
        lock.unlock()
        if let p, p.isRunning { p.terminate() }
    }

    /// Runs the request, streaming events as they come. Returns the final result.
    func run(_ request: ClaudeRequest, claudePath: String, onEvent: @escaping @Sendable (StreamEvent) -> Void) async throws -> RunResult {
        guard let claude = Self.locate(claudePath) else { throw ClaudeError.notInstalled }
        try? FileManager.default.createDirectory(at: request.directory, withIntermediateDirectories: true)

        var args = ["-p", "--output-format", "stream-json", "--verbose", "--model", request.model.alias,
                    "--dangerously-skip-permissions"]
        if let append = request.appendSystemPrompt { args += ["--append-system-prompt", append] }
        if let tools = request.tools { args += ["--tools", tools.joined(separator: ",")] }
        if let resume = request.resume { args += ["--resume", resume] }
        if request.cloud { args += ["--cloud"] }

        let p = Process()
        if request.sandboxed && !request.cloud && FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec") {
            p.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
            p.arguments = ["-p", Self.sandboxProfile(workspace: request.directory), claude] + args
        } else {
            p.executableURL = URL(fileURLWithPath: claude)
            p.arguments = args
        }
        p.currentDirectoryURL = request.directory
        p.environment = Self.environment()
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = stderr

        lock.lock()
        if cancelled { lock.unlock(); throw ClaudeError.cancelled }
        process = p
        lock.unlock()

        try p.run()
        // The prompt goes in on stdin, so nothing in it is ever read as a flag.
        stdin.fileHandleForWriting.write(Data(request.prompt.utf8))
        try? stdin.fileHandleForWriting.close()

        // Collect stderr off to the side for the error message.
        let errorBox = ErrorBox()
        let errReader = Task.detached {
            let data = (try? stderr.fileHandleForReading.readToEnd()) ?? Data()
            errorBox.set(String(data: data, encoding: .utf8) ?? "")
        }

        var result: RunResult?
        var usage = UsageLedger()
        var seen = Set<String>()
        var lastText = ""
        for try await line in stdout.fileHandleForReading.bytes.lines {
            for event in StreamJSON.parse(line: line) {
                switch event {
                case .usage(let id, let tier, let counts):
                    if seen.insert(id).inserted { usage.add(counts, tier) }
                case .text(let t):
                    lastText = t
                case .result(let r):
                    result = r
                default:
                    break
                }
                onEvent(event)
            }
        }
        p.waitUntilExit()
        _ = await errReader.value

        lock.lock()
        let wasCancelled = cancelled
        process = nil
        lock.unlock()
        if wasCancelled { throw ClaudeError.cancelled }

        if var r = result {
            if r.usage == nil { r.usage = usage }
            return r
        }
        let why = errorBox.value.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.terminationStatus == 0 && !lastText.isEmpty {
            return RunResult(ok: true, text: lastText, sessionID: "", usage: usage, error: nil)
        }
        throw ClaudeError.failed(why.isEmpty ? "Claude Code stopped (exit \(p.terminationStatus))." : String(why.suffix(600)))
    }
}

private final class ErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    func set(_ s: String) { lock.lock(); text = s; lock.unlock() }
    var value: String { lock.lock(); defer { lock.unlock() }; return text }
}
