import Foundation

// What Claude hands back at each stage, as JSON at the end of its reply. Every field
// is optional on the way in: a model that leaves one out still produces a usable report.

/// The plan Opus writes before anything runs: what it will do, with whom, how long it
/// should take, how much of the week it should use, and what will need the user.
public struct Forecast: Codable, Hashable, Sendable {
    public struct PlannedStep: Codable, Hashable, Sendable {
        public var title: String
        public var detail: String
        public var member: Member
        public var model: ModelTier

        public init(title: String, detail: String, member: Member, model: ModelTier) {
            self.title = title
            self.detail = detail
            self.member = member
            self.model = model
        }
    }

    public var title: String
    public var summary: String
    public var steps: [PlannedStep]
    public var hours: Double
    /// Estimated share of the weekly Max limit.
    public var usagePercent: Double
    public var needsYou: [String]
    public var assumptions: [String]
    /// Whether the result should be kept alive after it's done, and how.
    public var living: String?
    public var cadence: Cadence?

    public init(title: String, summary: String, steps: [PlannedStep], hours: Double, usagePercent: Double,
                needsYou: [String], assumptions: [String], living: String? = nil, cadence: Cadence? = nil) {
        self.title = title
        self.summary = summary
        self.steps = steps
        self.hours = hours
        self.usagePercent = usagePercent
        self.needsYou = needsYou
        self.assumptions = assumptions
        self.living = living
        self.cadence = cadence
    }

    public var members: [Member] {
        var seen: [Member] = []
        for s in steps where !seen.contains(s.member) { seen.append(s.member) }
        return seen
    }

    public static func parse(_ text: String) -> Forecast? {
        guard let o = JSONBlock.object(in: text) else { return nil }
        let steps = (o["steps"] as? [[String: Any]] ?? []).compactMap { s -> PlannedStep? in
            guard let title = JSONBlock.string(s["title"]), !title.isEmpty else { return nil }
            return PlannedStep(title: title, detail: JSONBlock.string(s["detail"]) ?? "",
                               member: Member(loose: JSONBlock.string(s["member"]) ?? "cloud"),
                               model: ModelTier(model: JSONBlock.string(s["model"]) ?? "sonnet"))
        }
        guard !steps.isEmpty else { return nil }
        let living = JSONBlock.string(o["living"]).flatMap { $0.isEmpty || $0.lowercased() == "none" ? nil : $0 }
        return Forecast(title: JSONBlock.string(o["title"]) ?? "Mission",
                        summary: JSONBlock.string(o["summary"]) ?? "",
                        steps: steps,
                        hours: JSONBlock.double(o["hours"]) ?? 1,
                        usagePercent: JSONBlock.double(o["usagePercent"]) ?? 5,
                        needsYou: JSONBlock.strings(o["needsYou"]),
                        assumptions: JSONBlock.strings(o["assumptions"]),
                        living: living,
                        cadence: JSONBlock.string(o["cadence"]).flatMap { Cadence(rawValue: $0.lowercased()) })
    }
}

/// What a step reports when it finishes.
public struct StepReport: Hashable, Sendable {
    public struct Ask: Hashable, Sendable {
        public var text: String
        public var kind: QuestionKind
        public var options: [String]
        public var reason: QuestionReason
    }

    public struct Handoff: Hashable, Sendable {
        public var member: Member
        public var title: String
        public var instructions: String
        /// For Comet: who to text. Anyone not on the allowlist needs a thumbs up first.
        public var recipient: String?
    }

    public var summary: String
    public var assumptions: [String]
    public var questions: [Ask]
    public var deliverables: [String]
    public var snapshots: [String]
    public var handoffs: [Handoff]
    public var skill: SkillProposal?

    public static func parse(_ text: String) -> StepReport {
        guard let o = JSONBlock.object(in: text) else {
            // No report: the reply itself is the summary.
            return StepReport(summary: JSONBlock.prose(text), assumptions: [], questions: [], deliverables: [],
                              snapshots: [], handoffs: [], skill: nil)
        }
        let asks = (o["questions"] as? [Any] ?? []).compactMap { item -> Ask? in
            if let text = item as? String, !text.isEmpty { return Ask(text: text, kind: .text, options: [], reason: .info) }
            guard let q = item as? [String: Any], let text = JSONBlock.string(q["text"]), !text.isEmpty else { return nil }
            let options = JSONBlock.strings(q["options"])
            let kind: QuestionKind
            switch (JSONBlock.string(q["kind"]) ?? "").lowercased() {
            case "yesno", "yes_no", "yes/no", "approval": kind = .yesNo
            case "choice": kind = options.isEmpty ? .text : .choice
            default: kind = options.isEmpty ? .text : .choice
            }
            return Ask(text: text, kind: kind, options: kind == .choice ? options : [],
                       reason: QuestionReason(rawValue: (JSONBlock.string(q["reason"]) ?? "info").lowercased()) ?? .info)
        }
        let handoffs = (o["handoffs"] as? [[String: Any]] ?? []).compactMap { h -> Handoff? in
            guard let title = JSONBlock.string(h["title"]), let instructions = JSONBlock.string(h["instructions"]) else { return nil }
            let member = Member(loose: JSONBlock.string(h["member"]) ?? "")
            guard member == .nova || member == .comet else { return nil }
            return Handoff(member: member, title: title, instructions: instructions, recipient: JSONBlock.string(h["recipient"]))
        }
        var skill: SkillProposal?
        if let s = o["newSkill"] as? [String: Any], let name = JSONBlock.string(s["name"]), let path = JSONBlock.string(s["path"]) {
            let target = Member(loose: JSONBlock.string(s["for"]) ?? "zenith")
            skill = SkillProposal(name: name, target: [.comet, .nova].contains(target) ? target : .zenith,
                                  summary: JSONBlock.string(s["summary"]) ?? "", path: path)
        }
        return StepReport(summary: JSONBlock.string(o["summary"]) ?? JSONBlock.prose(text),
                          assumptions: JSONBlock.strings(o["assumptions"]),
                          questions: asks,
                          deliverables: JSONBlock.strings(o["deliverables"]),
                          snapshots: JSONBlock.strings(o["snapshots"]),
                          handoffs: handoffs,
                          skill: skill)
    }
}

public enum ReviewReport {
    public static func parse(_ text: String) -> Review {
        guard let o = JSONBlock.object(in: text) else {
            return Review(pass: false, summary: JSONBlock.prose(text), issues: ["The reviewer didn't return a verdict."])
        }
        let pass = (o["pass"] as? Bool) ?? ((JSONBlock.string(o["pass"]) ?? "").lowercased() == "true")
        return Review(pass: pass, summary: JSONBlock.string(o["summary"]) ?? "", issues: JSONBlock.strings(o["issues"]))
    }
}

/// Finds the JSON object a reply ends with: the last ```json fence, else the last balanced {…}.
public enum JSONBlock {
    public static func object(in text: String) -> [String: Any]? {
        for candidate in candidates(text).reversed() {
            if let data = candidate.data(using: .utf8),
               let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return o }
        }
        return nil
    }

    static func candidates(_ text: String) -> [String] {
        var found: [String] = []
        // Fenced blocks.
        let parts = text.components(separatedBy: "```")
        if parts.count >= 3 {
            for i in stride(from: 1, to: parts.count - 1, by: 2) {
                var body = parts[i]
                if body.hasPrefix("json") { body.removeFirst(4) }
                found.append(body.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        // Balanced braces, outside strings.
        var depth = 0
        var start: String.Index?
        var inString = false
        var escaped = false
        for i in text.indices {
            let c = text[i]
            if inString {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                continue
            }
            if c == "\"" && depth > 0 { inString = true }
            else if c == "{" {
                if depth == 0 { start = i }
                depth += 1
            } else if c == "}" && depth > 0 {
                depth -= 1
                if depth == 0, let s = start { found.append(String(text[s...i])) }
            }
        }
        return found
    }

    /// The reply without its JSON, for when the summary field is missing.
    public static func prose(_ text: String) -> String {
        var t = text
        if let fence = t.range(of: "```") { t = String(t[..<fence.lowerBound]) }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > 1200 ? String(t.prefix(1199)) + "…" : t
    }

    static func string(_ v: Any?) -> String? {
        if let s = v as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }

    static func double(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Double(s.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    static func strings(_ v: Any?) -> [String] {
        (v as? [Any] ?? []).compactMap { string($0) }.filter { !$0.isEmpty }
    }
}
