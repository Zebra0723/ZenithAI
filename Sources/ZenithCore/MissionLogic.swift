import Foundation

public extension Mission {
    var column: BoardColumn {
        switch status {
        case .forecasting, .awaitingLaunch: return .forecast
        case .queued, .running, .paused, .reviewing: return .working
        case .needsYou: return .needsYou
        case .done, .failed, .stopped: return .done
        case .living: return .living
        }
    }

    var isActive: Bool { [.running, .reviewing].contains(status) }
    var isFinished: Bool { [.done, .failed, .stopped, .living].contains(status) }

    var openQuestions: [Question] { questions.filter { !$0.isAnswered } }

    /// The member doing something right now, for the mission view and the Galaxy strip.
    var activeMember: Member? {
        switch status {
        case .forecasting, .reviewing: return .zenith
        case .needsYou: return nil
        default: return steps.first(where: { $0.status == .running || $0.status == .waiting })?.member
        }
    }

    var progress: Double {
        guard !steps.isEmpty else { return 0 }
        let finished = steps.filter { [.done, .skipped, .failed].contains($0.status) }.count
        return Double(finished) / Double(steps.count)
    }

    /// The next step to start, skipping any waiting on an answer.
    var nextStep: Int? {
        steps.firstIndex { $0.status == .pending }
    }

    mutating func log(_ member: Member, _ kind: EventKind, _ text: String, file: String? = nil, at: Date = Date()) {
        timeline.append(TimelineEvent(at: at, member: member, kind: kind, text: text, file: file))
        updatedAt = at
    }

    /// Adds assumptions it doesn't already hold.
    mutating func assume(_ items: [String]) {
        for a in items where !assumptions.contains(a) { assumptions.append(a) }
    }

    /// Turns a forecast into the mission's plan.
    mutating func adopt(_ forecast: Forecast) {
        self.forecast = forecast
        title = forecast.title
        steps = forecast.steps.map { Step(title: $0.title, detail: $0.detail, member: $0.member, model: $0.model) }
        assumptions = forecast.assumptions
    }
}

/// Who Comet may text without a thumbs up.
public enum Allowlist {
    public static func normalize(_ contact: String) -> String {
        let trimmed = contact.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.contains("@") { return trimmed }
        let digits = trimmed.filter(\.isNumber)
        // Compare phone numbers on their last ten digits, so +1 and spacing don't matter.
        return digits.count > 10 ? String(digits.suffix(10)) : digits
    }

    /// "me" and "the user" are always allowed: Comet texting the user is the whole point.
    public static func allows(_ recipient: String?, list: [String]) -> Bool {
        guard let recipient, !recipient.isEmpty else { return true }
        let r = recipient.lowercased().trimmingCharacters(in: .whitespaces)
        if ["me", "user", "the user", "myself"].contains(r) { return true }
        let n = normalize(recipient)
        guard !n.isEmpty else {
            // A name, not a number or address: match it against names on the list.
            return list.contains { $0.lowercased().contains(r) }
        }
        return list.contains { normalize($0) == n || $0.lowercased().contains(r) }
    }
}

public extension LivingPlan {
    mutating func scheduleNext(from date: Date) {
        nextRun = date.addingTimeInterval(cadence.interval)
    }
}
