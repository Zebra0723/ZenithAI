import Foundation

// MARK: - Members and models

/// Who does a piece of a mission. Zenith itself plans and reviews; its cloud computer
/// does the heavy work; Nova and Comet are reached through Galaxy Link.
public enum Member: String, Codable, CaseIterable, Sendable {
    case zenith, cloud, nova, comet, nebula, orbit

    public var name: String {
        switch self {
        case .zenith: return "Zenith"
        case .cloud: return "Cloud computer"
        case .nova: return "Nova"
        case .comet: return "Comet"
        case .nebula: return "Nebula"
        case .orbit: return "Orbit"
        }
    }

    /// What the member is to the Galaxy, in a few words.
    public var role: String {
        switch self {
        case .zenith: return "Plans and reviews"
        case .cloud: return "Research, code, build, deploy"
        case .nova: return "Acts on the Mac"
        case .comet: return "Texts through iMessage"
        case .nebula: return "Thumbs up or down"
        case .orbit: return "Answers by voice"
        }
    }

    /// Members a step can be given to.
    public static let workers: [Member] = [.cloud, .nova, .comet]

    public init(loose value: String) {
        let v = value.lowercased()
        if v.contains("nova") || v.contains("mac") { self = .nova }
        else if v.contains("comet") || v.contains("imessage") || v.contains("text") || v.contains("phone") { self = .comet }
        else if v.contains("nebula") { self = .nebula }
        else if v.contains("orbit") { self = .orbit }
        else if v.contains("zenith") { self = .zenith }
        else { self = .cloud }
    }
}

/// The three Claude models Zenith routes between: Opus plans and reviews, Sonnet does
/// the bulk, Haiku takes the tiny steps.
public enum ModelTier: String, Codable, CaseIterable, Comparable, Sendable {
    case haiku, sonnet, opus

    public var name: String {
        switch self {
        case .haiku: return "Haiku 5.5"
        case .sonnet: return "Sonnet 5.5"
        case .opus: return "Opus 5.5"
        }
    }

    /// The alias Claude Code resolves to the latest model of the family.
    public var alias: String { rawValue }

    public init(model: String) {
        let m = model.lowercased()
        if m.contains("opus") { self = .opus }
        else if m.contains("haiku") { self = .haiku }
        else { self = .sonnet }
    }

    public static func < (a: ModelTier, b: ModelTier) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

// MARK: - Mission

public enum MissionStatus: String, Codable, Sendable {
    /// Opus is writing the forecast.
    case forecasting
    /// The forecast is ready; one thumbs up launches it.
    case awaitingLaunch
    /// Launched, waiting for room under the budget cap or for the overnight window.
    case queued
    case running
    /// Paused by the user, or by the governor before crossing the cap.
    case paused
    /// Everything that doesn't need the user is finished; the questions wait in one batch.
    case needsYou
    /// The Opus reviewer is checking the work against the brief.
    case reviewing
    case done
    /// Done, and kept working and up to date in the background.
    case living
    case failed
    case stopped
}

/// The five columns of the mission board.
public enum BoardColumn: String, CaseIterable, Identifiable, Sendable {
    case forecast, working, needsYou, done, living
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .forecast: return "Forecast"
        case .working: return "Working"
        case .needsYou: return "Needs you"
        case .done: return "Done"
        case .living: return "Living"
        }
    }
}

public enum StepStatus: String, Codable, Sendable {
    case pending, running, waiting, done, failed, skipped
}

public struct Step: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var member: Member
    public var model: ModelTier
    public var status: StepStatus = .pending
    public var summary: String = ""
    public var startedAt: Date?
    public var finishedAt: Date?
    /// The Galaxy Link task carrying this step, when Nova or Comet does it.
    public var linkTaskID: String?
    /// The Claude Code session, so a follow-up resumes with its context instead of re-reading everything.
    public var sessionID: String?
    /// For Comet: who to text.
    public var recipient: String?
    /// Finishes an earlier step with the user's answers, resuming that step's session.
    public var followUp: Bool = false

    public init(id: String = Ids.make("s"), title: String, detail: String, member: Member, model: ModelTier) {
        self.id = id
        self.title = title
        self.detail = detail
        self.member = member
        self.model = model
    }
}

public enum QuestionKind: String, Codable, Sendable {
    case yesNo, choice, text
}

/// Why a question has to reach the user. Spending money and posting publicly always
/// need a thumbs up; so does texting someone who isn't on the allowlist.
public enum QuestionReason: String, Codable, Sendable {
    case info, spend, publish, contact, install

    public var label: String {
        switch self {
        case .info: return "Decision"
        case .spend: return "Spends money"
        case .publish: return "Posts publicly"
        case .contact: return "Contacts someone"
        case .install: return "New ability"
        }
    }
}

public struct Question: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var stepID: String?
    public var text: String
    public var kind: QuestionKind
    public var options: [String]
    public var reason: QuestionReason
    public var answer: String?
    public var askedAt: Date
    /// For an install question: the skill to install when the answer is yes.
    public var skill: SkillProposal?
    /// The answer has been acted on.
    public var applied: Bool = false

    public init(id: String = Ids.make("q"), stepID: String?, text: String, kind: QuestionKind, options: [String] = [],
                reason: QuestionReason = .info, askedAt: Date = Date(), skill: SkillProposal? = nil) {
        self.id = id
        self.stepID = stepID
        self.text = text
        self.kind = kind
        self.options = options
        self.reason = reason
        self.askedAt = askedAt
        self.skill = skill
    }

    public var isAnswered: Bool { !(answer ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public var approved: Bool { answer?.lowercased() == "yes" }
}

/// A new tool, script or skill the cloud computer built and tested during a mission.
public struct SkillProposal: Codable, Hashable, Sendable {
    public var name: String
    /// Which member gets it: comet, nova or zenith.
    public var target: Member
    public var summary: String
    /// Folder inside the mission's workspace holding the skill (a SKILL.md and its files).
    public var path: String
    public var installed: Bool = false

    public init(name: String, target: Member, summary: String, path: String) {
        self.name = name
        self.target = target
        self.summary = summary
        self.path = path
    }
}

public enum EventKind: String, Codable, Sendable {
    case note, plan, step, tool, handoff, message, snapshot, question, answer, budget, review, done, error, living
}

/// One moment on a mission's timeline. Replay scrubs through these.
public struct TimelineEvent: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var at: Date
    public var member: Member
    public var kind: EventKind
    public var text: String
    /// A snapshot image in the mission's folder, for kind == .snapshot.
    public var file: String?

    public init(id: String = Ids.make("e"), at: Date = Date(), member: Member, kind: EventKind, text: String, file: String? = nil) {
        self.id = id
        self.at = at
        self.member = member
        self.kind = kind
        self.text = text
        self.file = file
    }
}

public enum Cadence: String, Codable, CaseIterable, Sendable {
    case hourly, daily, weekly

    public var interval: TimeInterval {
        switch self {
        case .hourly: return 3600
        case .daily: return 86_400
        case .weekly: return 7 * 86_400
        }
    }

    public var title: String { rawValue.capitalized }
}

public struct LivingRun: Codable, Hashable, Sendable {
    public var at: Date
    public var ok: Bool
    public var note: String
    public var units: Double

    public init(at: Date, ok: Bool, note: String, units: Double) {
        self.at = at
        self.ok = ok
        self.note = note
        self.units = units
    }
}

/// What keeps a finished result alive: a silent upkeep run on a cadence.
public struct LivingPlan: Codable, Hashable, Sendable {
    public var task: String
    public var cadence: Cadence
    public var enabled: Bool = true
    public var nextRun: Date
    public var runs: [LivingRun] = []

    public init(task: String, cadence: Cadence, nextRun: Date) {
        self.task = task
        self.cadence = cadence
        self.nextRun = nextRun
    }
}

/// Where a mission's brief came from.
public enum MissionSource: String, Codable, Sendable {
    case app, comet, orbit, nova, nebula, link

    public var title: String {
        switch self {
        case .app: return "Zenith"
        case .link: return "Galaxy Link"
        default: return rawValue.capitalized
        }
    }
}

public struct Mission: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var brief: String
    /// The conversation it was made from, when it came from "Make it a mission".
    public var context: String
    public var source: MissionSource
    public var createdAt: Date
    public var updatedAt: Date
    public var launchedAt: Date?
    public var finishedAt: Date?

    public var status: MissionStatus
    /// One line on why it's in this status: "Waiting for the overnight window", "Paused at the budget cap".
    public var statusNote: String = ""

    public var forecast: Forecast?
    public var steps: [Step] = []
    public var questions: [Question] = []
    public var assumptions: [String] = []
    public var timeline: [TimelineEvent] = []
    public var usage = UsageLedger()

    public var summary: String = ""
    /// Paths in the workspace, or URLs, of what the mission made.
    public var deliverables: [String] = []
    public var review: Review?
    public var living: LivingPlan?
    public var skills: [SkillProposal] = []

    /// The Galaxy Link task that asked for this mission, answered when it's done.
    public var linkTaskID: String?
    /// The pending Nebula approval for the launch or for the batch of questions.
    public var linkApprovalID: String?
    /// The user changed course mid-mission; the next step reads this first.
    public var redirect: String?
    /// Ran on the cloud computer (Claude Code cloud sessions) rather than the sandbox on the Mac.
    public var onCloud: Bool = false
    /// Times the reviewer sent the work back. One fix round, then it's done either way.
    public var fixRounds: Int = 0

    public init(id: String = Ids.make("m"), title: String, brief: String, context: String = "", source: MissionSource = .app,
                now: Date = Date()) {
        self.id = id
        self.title = title
        self.brief = brief
        self.context = context
        self.source = source
        self.createdAt = now
        self.updatedAt = now
        self.status = .forecasting
    }
}

public struct Review: Codable, Hashable, Sendable {
    public var pass: Bool
    public var summary: String
    public var issues: [String]

    public init(pass: Bool, summary: String, issues: [String]) {
        self.pass = pass
        self.summary = summary
        self.issues = issues
    }
}

// MARK: - Ids

public enum Ids {
    /// Short, sortable, readable ids: m_lq3k9x2a.
    public static func make(_ prefix: String, now: Date = Date()) -> String {
        let time = String(UInt64(now.timeIntervalSince1970 * 1000), radix: 36)
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        let tail = String((0..<4).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] })
        return "\(prefix)_\(time)\(tail)"
    }
}
