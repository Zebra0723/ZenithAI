import Foundation

/// One line of `claude -p --output-format stream-json --verbose`, reduced to what Zenith shows
/// and counts.
public enum StreamEvent: Equatable, Sendable {
    case started(session: String, model: String)
    case text(String)
    /// A tool call, summarized for the timeline: "Bash: npm run build", "Edit: index.html".
    case tool(name: String, summary: String)
    /// Usage of one model message, keyed by its id so repeats count once.
    case usage(messageID: String, model: ModelTier, counts: TokenCounts)
    case result(RunResult)
}

public struct RunResult: Equatable, Sendable {
    public var ok: Bool
    public var text: String
    public var sessionID: String
    /// Per-model usage for the whole run, when Claude Code reports it.
    public var usage: UsageLedger?
    public var error: String?

    public init(ok: Bool, text: String, sessionID: String, usage: UsageLedger?, error: String?) {
        self.ok = ok
        self.text = text
        self.sessionID = sessionID
        self.usage = usage
        self.error = error
    }
}

public enum StreamJSON {
    public static func parse(line: String) -> [StreamEvent] {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { return [] }

        switch type {
        case "system":
            guard object["subtype"] as? String == "init" else { return [] }
            return [.started(session: object["session_id"] as? String ?? "", model: object["model"] as? String ?? "")]

        case "assistant":
            guard let message = object["message"] as? [String: Any] else { return [] }
            var events: [StreamEvent] = []
            for block in message["content"] as? [[String: Any]] ?? [] {
                switch block["type"] as? String {
                case "text":
                    if let text = block["text"] as? String, !text.isEmpty { events.append(.text(text)) }
                case "tool_use":
                    let name = block["name"] as? String ?? "tool"
                    events.append(.tool(name: name, summary: toolSummary(name, block["input"] as? [String: Any] ?? [:])))
                default:
                    break
                }
            }
            if let usage = message["usage"] as? [String: Any], let id = message["id"] as? String {
                events.append(.usage(messageID: id, model: ModelTier(model: message["model"] as? String ?? ""),
                                     counts: counts(usage)))
            }
            return events

        case "result":
            let isError = object["is_error"] as? Bool ?? (object["subtype"] as? String != "success")
            var ledger: UsageLedger?
            if let models = object["modelUsage"] as? [String: Any], !models.isEmpty {
                var l = UsageLedger()
                for (model, value) in models {
                    guard let u = value as? [String: Any] else { continue }
                    l.add(TokenCounts(input: int(u["inputTokens"]), output: int(u["outputTokens"]),
                                      cacheWrite: int(u["cacheCreationInputTokens"]), cacheRead: int(u["cacheReadInputTokens"])),
                          ModelTier(model: model))
                }
                ledger = l
            }
            let text = object["result"] as? String ?? ""
            return [.result(RunResult(ok: !isError, text: text, sessionID: object["session_id"] as? String ?? "",
                                      usage: ledger, error: isError ? (text.isEmpty ? (object["subtype"] as? String ?? "error") : text) : nil))]

        default:
            return []
        }
    }

    static func counts(_ usage: [String: Any]) -> TokenCounts {
        TokenCounts(input: int(usage["input_tokens"]), output: int(usage["output_tokens"]),
                    cacheWrite: int(usage["cache_creation_input_tokens"]), cacheRead: int(usage["cache_read_input_tokens"]))
    }

    static func int(_ value: Any?) -> Int {
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        if let n = value as? NSNumber { return n.intValue }
        return 0
    }

    public static func toolSummary(_ name: String, _ input: [String: Any]) -> String {
        func clip(_ s: String, _ n: Int = 90) -> String {
            let line = s.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? s
            return line.count > n ? String(line.prefix(n - 1)) + "…" : line
        }
        let detail: String
        if let command = input["command"] as? String { detail = clip(command) }
        else if let path = (input["file_path"] ?? input["path"] ?? input["notebook_path"]) as? String {
            detail = (path as NSString).lastPathComponent
        } else if let url = input["url"] as? String { detail = URL(string: url)?.host ?? clip(url) }
        else if let query = input["query"] as? String { detail = clip(query) }
        else if let pattern = input["pattern"] as? String { detail = clip(pattern) }
        else if let description = input["description"] as? String { detail = clip(description) }
        else { detail = "" }
        return detail.isEmpty ? name : "\(name): \(detail)"
    }
}

/// Usage from Claude Code's own transcripts (~/.claude/projects/*/*.jsonl), which hold
/// every run on this Mac: Zenith's sandbox runs and anything else using Claude Code.
public enum TranscriptUsage {
    public struct Entry: Equatable, Sendable {
        public var key: String
        public var at: Date
        public var model: ModelTier
        public var counts: TokenCounts
    }

    public static func parse(line: String) -> Entry? {
        // Cheap check first: most lines aren't assistant messages with usage.
        guard line.contains("\"usage\""), line.contains("\"assistant\""),
              let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "assistant",
              let message = object["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let stamp = object["timestamp"] as? String,
              let at = parseDate(stamp) else { return nil }
        let id = message["id"] as? String ?? ""
        let request = object["requestId"] as? String ?? ""
        let key = id.isEmpty && request.isEmpty ? (object["uuid"] as? String ?? stamp) : "\(id)|\(request)"
        return Entry(key: key, at: at, model: ModelTier(model: message["model"] as? String ?? ""),
                     counts: StreamJSON.counts(usage))
    }

    static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
