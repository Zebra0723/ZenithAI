import Foundation
import ZenithCore

/// The Zenith connector: keeps Zenith present in Galaxy Link and takes the work other
/// bodies send it. A handoff with the power `missions` is a brief ("Zenith: …" texted to
/// Comet, "make it a mission" from any conversation); `mission_status`, or anything that
/// reads like "how's my mission?", is answered straight from the board for no tokens.
@MainActor
final class Connector: ObservableObject {
    static let shared = Connector()

    @Published private(set) var connected = false
    @Published private(set) var bodies: [GalaxyLink.Body] = []

    private let link = GalaxyLink.shared
    private var loops: [Task<Void, Never>] = []

    func start() {
        guard loops.isEmpty else { return }
        // Presence: hello, then a heartbeat every minute.
        loops.append(Task {
            while !Task.isCancelled {
                let up = await link.heartbeat()
                connected = up
                if up, let b = await link.bodies() { bodies = b }
                try? await Task.sleep(for: .seconds(up ? 60 : 30))
            }
        })
        // Work: a long poll for the next task.
        loops.append(Task {
            while !Task.isCancelled {
                guard connected else {
                    try? await Task.sleep(for: .seconds(15))
                    continue
                }
                if let task = await link.nextTask() {
                    await handle(task)
                } else {
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        })
    }

    func stop() async {
        loops.forEach { $0.cancel() }
        loops.removeAll()
        await link.goodbye()
    }

    private func handle(_ task: GalaxyLink.LinkTask) async {
        let missions = Store.shared.missions
        if task.power == "mission_status" || Self.asksForStatus(task.title + " " + task.instructions) {
            await link.finish(task.id, ok: true, result: Prompts.status(missions))
            return
        }
        let source = MissionSource(rawValue: task.from) ?? .link
        let (brief, context) = Self.split(task.instructions.isEmpty ? task.title : task.instructions)
        Commander.shared.create(brief: brief, context: context, source: source, linkTaskID: task.id)
        await link.progress(task.id, note: "Zenith is writing the forecast. It launches with one thumbs up, in Zenith or with Nebula.")
    }

    static func asksForStatus(_ text: String) -> Bool {
        let t = text.lowercased().replacingOccurrences(of: "’", with: "'")
        let phrases = ["how's my mission", "how is my mission", "hows my mission", "how are my missions", "mission status",
                       "status of my mission", "how's the mission", "how is the mission", "missions doing"]
        return phrases.contains { t.contains($0) }
    }

    /// "Make it a mission" sends the conversation along: a "Context:" section, when there is
    /// one, is the conversation; the rest is the brief.
    static func split(_ text: String) -> (brief: String, context: String) {
        for marker in ["\n\nContext:", "\n\nConversation:", "\nContext:\n", "\nConversation:\n"] {
            if let r = text.range(of: marker) {
                let brief = String(text[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let context = String(text[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !brief.isEmpty { return (brief, context) }
            }
        }
        var brief = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if brief.lowercased().hasPrefix("zenith:") { brief = String(brief.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
        return (brief, "")
    }
}
