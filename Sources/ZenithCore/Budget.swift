import Foundation

/// The user's numbers for the Galaxy budget governor.
public struct BudgetSettings: Codable, Hashable, Sendable {
    /// The whole Galaxy stays under this share of the weekly Max limit.
    public var capPercent: Double = 50
    /// How many usage units make one percent of the weekly limit. Set by calibration.
    public var unitsPerPercent: Double = 10
    /// Weekly shares for members whose usage this Mac can't measure (Comet runs on its
    /// server, Nova on its own key until it moves to the plan). The plan's ballpark midpoints.
    public var others: [String: Double] = ["comet": 15, "nova": 10, "orbit": 2, "nebula": 0]
    /// When the weekly limit resets. Calendar weekday: 1 is Sunday, 2 is Monday.
    public var resetWeekday: Int = 2
    public var resetHour: Int = 0
    /// Heavy work runs in this window, when the limit would otherwise go unused.
    public var overnightStart: Int = 1
    public var overnightEnd: Int = 7
    public var preferOvernight: Bool = true
    /// A mission forecast at or above this share counts as heavy.
    public var heavyPercent: Double = 5
    /// Pause this far below the cap, so the step in flight can't carry the Galaxy over it.
    public var margin: Double = 1
    public var calibration: Calibration?

    public init() {}

    public var othersWeekly: Double { others.values.reduce(0, +) }
}

/// "Claude's usage page said X% at this moment", paired with what Zenith had measured by then.
public struct Calibration: Codable, Hashable, Sendable {
    public var at: Date
    public var shownPercent: Double

    public init(at: Date, shownPercent: Double) {
        self.at = at
        self.shownPercent = shownPercent
    }
}

/// Where the week stands.
public struct BudgetReading: Hashable, Sendable {
    public var weekStart: Date
    public var weekEnd: Date
    /// Claude Code on this Mac (Zenith's sandbox runs included), this week.
    public var macPercent: Double
    /// Zenith's runs on the cloud computer this week.
    public var cloudPercent: Double
    /// Zenith alone (sandbox and cloud), this week, for the breakdown.
    public var zenithPercent: Double
    /// Estimated shares of the members this Mac can't measure, so far this week.
    public var othersPercent: Double
    /// The whole Galaxy's estimated share of the weekly limit.
    public var usedPercent: Double
    public var capPercent: Double
    public var calibrated: Bool

    public var roomPercent: Double { max(0, capPercent - usedPercent) }
}

public enum LaunchDecision: Equatable, Sendable {
    case go
    /// Not enough room under the cap; the reason says when there will be.
    case waitForRoom(String)
    /// Heavy work waits for the overnight window.
    case waitForNight(Date)
    /// Usage is tight, so parallel missions queue behind the running one.
    case waitForTurn
}

/// Keeps the whole Galaxy under its share of the weekly Max limit: decides when a mission
/// may start, sends heavy work overnight, queues parallel missions when usage is tight,
/// and pauses before the cap is crossed.
public struct BudgetGovernor: Sendable {
    public var settings: BudgetSettings
    public var calendar: Calendar

    public init(settings: BudgetSettings, calendar: Calendar = .current) {
        self.settings = settings
        self.calendar = calendar
    }

    public static let week: TimeInterval = 7 * 86_400

    /// The most recent reset at or before `now`.
    public func weekStart(for now: Date) -> Date {
        var parts = DateComponents()
        parts.weekday = settings.resetWeekday
        parts.hour = settings.resetHour
        parts.minute = 0
        parts.second = 0
        return calendar.nextDate(after: now.addingTimeInterval(1), matching: parts, matchingPolicy: .nextTime,
                                 direction: .backward) ?? now.addingTimeInterval(-Self.week)
    }

    /// - Parameters:
    ///   - macUnits: usage units of Claude Code on this Mac since a date.
    ///   - cloudUnits: usage units of Zenith's cloud runs since a date.
    ///   - zenithUnits: usage units of every Zenith run since a date.
    public func reading(now: Date, macUnits: (Date) -> Double, cloudUnits: (Date) -> Double,
                        zenithUnits: (Date) -> Double) -> BudgetReading {
        let start = weekStart(for: now)
        let upp = max(settings.unitsPerPercent, 0.0001)
        let othersRate = settings.othersWeekly / Self.week
        let mac = macUnits(start) / upp
        let cloud = cloudUnits(start) / upp
        let elapsed = now.timeIntervalSince(start)

        var used: Double
        var calibrated = false
        if let cal = settings.calibration, cal.at >= start, cal.at <= now {
            // The usage page is the truth at the moment it was read; measure from there.
            let since = (macUnits(cal.at) + cloudUnits(cal.at)) / upp
            used = cal.shownPercent + since + othersRate * now.timeIntervalSince(cal.at)
            calibrated = true
        } else {
            used = mac + cloud + othersRate * elapsed
        }
        used = max(0, used)
        return BudgetReading(weekStart: start, weekEnd: start.addingTimeInterval(Self.week),
                             macPercent: mac, cloudPercent: cloud, zenithPercent: zenithUnits(start) / upp,
                             othersPercent: othersRate * elapsed, usedPercent: used,
                             capPercent: settings.capPercent, calibrated: calibrated)
    }

    public func decide(estimatePercent: Double, reading: BudgetReading, running: Int, now: Date) -> LaunchDecision {
        let ceiling = settings.capPercent - settings.margin
        if reading.usedPercent + estimatePercent > ceiling {
            let left = max(0, ceiling - reading.usedPercent)
            let f = DateFormatter()
            f.calendar = calendar
            f.timeZone = calendar.timeZone
            f.dateFormat = "EEEE ha"
            let reset = f.string(from: reading.weekEnd)
            return .waitForRoom(String(format: "Needs about %.0f%% of the week and %.0f%% is left under the cap. Room comes back %@.",
                                       estimatePercent, left, reset))
        }
        if settings.preferOvernight, estimatePercent >= settings.heavyPercent, !isOvernight(now) {
            return .waitForNight(nextOvernight(after: now))
        }
        // Tight: less than two of these left. Run one at a time.
        if running > 0, ceiling - reading.usedPercent < estimatePercent * 2 {
            return .waitForTurn
        }
        return .go
    }

    /// True once the Galaxy is within the margin of the cap: running missions pause and report.
    public func mustPause(_ reading: BudgetReading) -> Bool {
        reading.usedPercent >= settings.capPercent - settings.margin
    }

    // MARK: - Overnight

    public func isOvernight(_ date: Date) -> Bool {
        let hour = calendar.component(.hour, from: date)
        let (s, e) = (settings.overnightStart, settings.overnightEnd)
        if s == e { return true }
        return s < e ? (hour >= s && hour < e) : (hour >= s || hour < e)
    }

    public func nextOvernight(after date: Date) -> Date {
        if isOvernight(date) { return date }
        var parts = DateComponents()
        parts.hour = settings.overnightStart
        parts.minute = 0
        parts.second = 0
        return calendar.nextDate(after: date, matching: parts, matchingPolicy: .nextTime) ?? date
    }
}
