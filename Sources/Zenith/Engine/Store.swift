import Foundation
import ZenithCore

enum Backend: String, Codable, CaseIterable {
    /// An isolated sandbox on this Mac (Claude Code under a write-confined profile). Always works.
    case sandbox
    /// Claude Code cloud sessions: included in the plan and running with the Mac off, once verified.
    case cloud
}

struct ZenithSettings: Codable, Equatable {
    var budget = BudgetSettings()
    /// Comet may text these people without a thumbs up.
    var allowlist: [String] = []
    var backend: Backend = .sandbox
    /// When the cloud check last passed. Cloud runs only after it has.
    var cloudVerifiedAt: Date?
    /// Confine the worker's writes to the mission's workspace.
    var sandboxed = true
    /// Where the claude command is, when it isn't somewhere Zenith looks.
    var claudePath = ""
    /// Nova acts on the Mac during missions.
    var useNova = true
    /// Comet texts during missions.
    var useComet = true
    /// Arm Nebula's approval mode for launches and yes-or-no questions.
    var nebulaApprovals = true
    /// The one text when a mission is done.
    var doneText = true
    /// Missions that may run at the same time, before the governor's own limits.
    var maxParallel = 3

    init() {}

    init(from decoder: Decoder) throws {
        // Settings saved by an older Zenith keep their values; new ones start at their defaults.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ZenithSettings()
        budget = (try? c.decode(BudgetSettings.self, forKey: .budget)) ?? d.budget
        allowlist = (try? c.decode([String].self, forKey: .allowlist)) ?? d.allowlist
        backend = (try? c.decode(Backend.self, forKey: .backend)) ?? d.backend
        cloudVerifiedAt = try? c.decode(Date.self, forKey: .cloudVerifiedAt)
        sandboxed = (try? c.decode(Bool.self, forKey: .sandboxed)) ?? d.sandboxed
        claudePath = (try? c.decode(String.self, forKey: .claudePath)) ?? d.claudePath
        useNova = (try? c.decode(Bool.self, forKey: .useNova)) ?? d.useNova
        useComet = (try? c.decode(Bool.self, forKey: .useComet)) ?? d.useComet
        nebulaApprovals = (try? c.decode(Bool.self, forKey: .nebulaApprovals)) ?? d.nebulaApprovals
        doneText = (try? c.decode(Bool.self, forKey: .doneText)) ?? d.doneText
        maxParallel = (try? c.decode(Int.self, forKey: .maxParallel)) ?? d.maxParallel
    }
}

/// One run of Claude for Zenith, for the budget: when, how much, and where.
struct RunRecord: Codable {
    var at: Date
    var units: Double
    var cloud: Bool
}

/// Missions, settings and Zenith's own usage, on disk in ~/Library/Application Support/Zenith.
@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published private(set) var missions: [Mission] = []
    @Published var settings = ZenithSettings() {
        didSet { if settings != oldValue { write(settings, to: dir.appendingPathComponent("settings.json")) } }
    }
    private(set) var runs: [RunRecord] = []

    let dir: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Zenith", isDirectory: true)
        try? FileManager.default.createDirectory(at: missionsDir, withIntermediateDirectories: true)
        load()
    }

    var missionsDir: URL { dir.appendingPathComponent("Missions", isDirectory: true) }

    func folder(_ id: String) -> URL { missionsDir.appendingPathComponent(id, isDirectory: true) }
    func workspace(_ id: String) -> URL { folder(id).appendingPathComponent("workspace", isDirectory: true) }
    func snapshots(_ id: String) -> URL { folder(id).appendingPathComponent("snapshots", isDirectory: true) }

    // MARK: - Missions

    func mission(_ id: String) -> Mission? { missions.first { $0.id == id } }

    func add(_ mission: Mission) {
        missions.insert(mission, at: 0)
        try? FileManager.default.createDirectory(at: workspace(mission.id), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: snapshots(mission.id), withIntermediateDirectories: true)
        save(mission)
    }

    /// Changes a mission and saves it. Returns the changed mission. With persist false (for the
    /// stream of tool calls) it's saved on the next flush instead.
    @discardableResult
    func update(_ id: String, persist: Bool = true, _ change: (inout Mission) -> Void) -> Mission? {
        guard let i = missions.firstIndex(where: { $0.id == id }) else { return nil }
        var m = missions[i]
        change(&m)
        m.updatedAt = Date()
        // A long mission's timeline stays useful for Replay without growing forever.
        if m.timeline.count > 4000 { m.timeline.removeFirst(m.timeline.count - 4000) }
        missions[i] = m
        if persist {
            dirty.remove(id)
            save(m)
        } else {
            dirty.insert(id)
        }
        return m
    }

    private var dirty = Set<String>()

    func flush() {
        for id in dirty { if let m = mission(id) { save(m) } }
        dirty.removeAll()
    }

    func delete(_ id: String) {
        missions.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: folder(id))
    }

    private func save(_ m: Mission) {
        write(m, to: folder(m.id).appendingPathComponent("mission.json"))
    }

    // MARK: - Usage

    func record(_ units: Double, cloud: Bool) {
        guard units > 0 else { return }
        runs.append(RunRecord(at: Date(), units: units, cloud: cloud))
        // Two weeks is all the budget ever looks at.
        let cutoff = Date().addingTimeInterval(-15 * 86_400)
        runs.removeAll { $0.at < cutoff }
        write(runs, to: dir.appendingPathComponent("runs.json"))
    }

    func zenithUnits(since: Date) -> Double { runs.filter { $0.at >= since }.reduce(0) { $0 + $1.units } }
    func cloudUnits(since: Date) -> Double { runs.filter { $0.at >= since && $0.cloud }.reduce(0) { $0 + $1.units } }

    // MARK: - Disk

    private func load() {
        if let data = try? Data(contentsOf: dir.appendingPathComponent("settings.json")),
           let s = try? decoder.decode(ZenithSettings.self, from: data) { settings = s }
        if let data = try? Data(contentsOf: dir.appendingPathComponent("runs.json")),
           let r = try? decoder.decode([RunRecord].self, from: data) { runs = r }
        let folders = (try? FileManager.default.contentsOfDirectory(at: missionsDir, includingPropertiesForKeys: nil)) ?? []
        missions = folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("mission.json")) else { return nil }
            return try? decoder.decode(Mission.self, from: data)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? encoder.encode(value) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
