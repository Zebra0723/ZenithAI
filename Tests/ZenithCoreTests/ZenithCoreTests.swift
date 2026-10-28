import XCTest
@testable import ZenithCore

final class ForecastTests: XCTestCase {
    func testParsesFencedForecast() {
        let reply = """
        Here's the plan.
        ```json
        {"title": "Launch the bakery site", "summary": "Build and deploy it.",
         "steps": [{"title": "Build", "detail": "Astro site", "member": "cloud", "model": "sonnet"},
                   {"title": "Get the logo", "detail": "From Mail", "member": "nova", "model": "haiku"},
                   {"title": "Tell Sam", "detail": "Text the link", "member": "Comet", "model": "haiku"}],
         "hours": 3, "usagePercent": "7%", "needsYou": ["Domain purchase"], "assumptions": ["Free hosting"],
         "living": "Keep the menu current", "cadence": "weekly"}
        ```
        """
        let f = Forecast.parse(reply)
        XCTAssertEqual(f?.title, "Launch the bakery site")
        XCTAssertEqual(f?.steps.map(\.member), [.cloud, .nova, .comet])
        XCTAssertEqual(f?.steps.map(\.model), [.sonnet, .haiku, .haiku])
        XCTAssertEqual(f?.usagePercent, 7)
        XCTAssertEqual(f?.cadence, .weekly)
        XCTAssertEqual(f?.living, "Keep the menu current")
        XCTAssertEqual(f?.members, [.cloud, .nova, .comet])
    }

    func testRejectsForecastWithoutSteps() {
        XCTAssertNil(Forecast.parse(#"{"title": "x", "steps": []}"#))
        XCTAssertNil(Forecast.parse("no json here"))
    }

    func testLivingNoneMeansNotLiving() {
        let f = Forecast.parse(#"{"title":"t","steps":[{"title":"a"}],"living":"none"}"#)
        XCTAssertNil(f?.living)
        XCTAssertEqual(f?.steps.first?.member, .cloud)
        XCTAssertEqual(f?.steps.first?.model, .sonnet)
    }
}

final class StepReportTests: XCTestCase {
    func testTakesTheLastJSONObject() {
        let reply = """
        I tried {"not": "this"} first.
        Done. The site is live.
        {"summary": "Built and deployed", "assumptions": ["Used Vercel"],
         "questions": [{"text": "Buy bakery.com for $12?", "kind": "yesno", "reason": "spend"},
                       {"text": "Which photo?", "kind": "choice", "options": ["A", "B"]}],
         "deliverables": ["https://bakery.vercel.app"], "snapshots": [".zenith/snapshots/home.png"],
         "handoffs": [{"member": "comet", "title": "Tell Sam", "instructions": "Send the link", "recipient": "Sam"},
                      {"member": "orbit", "title": "ignored", "instructions": "x"}],
         "newSkill": {"name": "menu-sync", "for": "comet", "summary": "Syncs the menu", "path": "skills/menu-sync"}}
        """
        let r = StepReport.parse(reply)
        XCTAssertEqual(r.summary, "Built and deployed")
        XCTAssertEqual(r.questions.count, 2)
        XCTAssertEqual(r.questions[0].kind, .yesNo)
        XCTAssertEqual(r.questions[0].reason, .spend)
        XCTAssertEqual(r.questions[1].kind, .choice)
        XCTAssertEqual(r.questions[1].options, ["A", "B"])
        XCTAssertEqual(r.handoffs.count, 1)
        XCTAssertEqual(r.handoffs.first?.recipient, "Sam")
        XCTAssertEqual(r.skill?.target, .comet)
        XCTAssertEqual(r.deliverables, ["https://bakery.vercel.app"])
    }

    func testNoJSONFallsBackToProse() {
        let r = StepReport.parse("All done, nothing else.")
        XCTAssertEqual(r.summary, "All done, nothing else.")
        XCTAssertTrue(r.questions.isEmpty)
    }

    func testBracesInsideStringsDontBreakParsing() {
        let r = StepReport.parse(#"{"summary": "Wrote a } and a { in the CSS"}"#)
        XCTAssertEqual(r.summary, "Wrote a } and a { in the CSS")
    }

    func testReview() {
        XCTAssertTrue(ReviewReport.parse(#"```json\#n{"pass": true, "summary": "Good", "issues": []}\#n```"#).pass)
        let failed = ReviewReport.parse(#"{"pass": false, "summary": "Broken", "issues": ["404 on /menu"]}"#)
        XCTAssertFalse(failed.pass)
        XCTAssertEqual(failed.issues, ["404 on /menu"])
        XCTAssertFalse(ReviewReport.parse("looks fine to me").pass)
    }
}

final class StreamTests: XCTestCase {
    func testInitToolsUsageAndResult() {
        let lines = [
            #"{"type":"system","subtype":"init","session_id":"abc","model":"claude-sonnet-5-5"}"#,
            #"{"type":"assistant","message":{"id":"msg_1","model":"claude-sonnet-5-5","content":[{"type":"text","text":"Building."},{"type":"tool_use","name":"Bash","input":{"command":"npm run build\nnpm test"}}],"usage":{"input_tokens":10,"output_tokens":20,"cache_creation_input_tokens":30,"cache_read_input_tokens":40}}}"#,
            #"{"type":"assistant","message":{"id":"msg_2","model":"claude-sonnet-5-5","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/w/site/index.html"}}]}}"#,
            #"{"type":"result","subtype":"success","is_error":false,"result":"Done","session_id":"abc","modelUsage":{"claude-opus-5-5":{"inputTokens":100,"outputTokens":50,"cacheReadInputTokens":1000,"cacheCreationInputTokens":0},"claude-haiku-5-5":{"inputTokens":5,"outputTokens":5}}}"#,
        ]
        let events = lines.flatMap(StreamJSON.parse(line:))
        XCTAssertEqual(events[0], .started(session: "abc", model: "claude-sonnet-5-5"))
        XCTAssertEqual(events[1], .text("Building."))
        XCTAssertEqual(events[2], .tool(name: "Bash", summary: "Bash: npm run build"))
        XCTAssertEqual(events[3], .usage(messageID: "msg_1", model: .sonnet, counts: TokenCounts(input: 10, output: 20, cacheWrite: 30, cacheRead: 40)))
        XCTAssertEqual(events[4], .tool(name: "Edit", summary: "Edit: index.html"))
        guard case .result(let r) = events[5] else { return XCTFail("no result") }
        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.text, "Done")
        XCTAssertEqual(r.usage?.counts(.opus), TokenCounts(input: 100, output: 50, cacheWrite: 0, cacheRead: 1000))
        XCTAssertEqual(r.usage?.counts(.haiku).output, 5)
    }

    func testErrorResult() {
        guard case .result(let r) = StreamJSON.parse(line: #"{"type":"result","subtype":"error_max_turns","is_error":true,"session_id":"x"}"#).first else {
            return XCTFail("no result")
        }
        XCTAssertFalse(r.ok)
        XCTAssertEqual(r.error, "error_max_turns")
    }

    func testIgnoresJunk() {
        XCTAssertTrue(StreamJSON.parse(line: "not json").isEmpty)
        XCTAssertTrue(StreamJSON.parse(line: #"{"type":"user","message":{}}"#).isEmpty)
    }

    func testTranscriptLine() {
        let line = #"{"type":"assistant","timestamp":"2026-10-27T10:00:00.123Z","requestId":"req_1","message":{"id":"msg_9","model":"claude-opus-5-5","usage":{"input_tokens":1000,"output_tokens":200}}}"#
        let e = TranscriptUsage.parse(line: line)
        XCTAssertEqual(e?.model, .opus)
        XCTAssertEqual(e?.key, "msg_9|req_1")
        XCTAssertEqual(e?.counts.output, 200)
        XCTAssertNil(TranscriptUsage.parse(line: #"{"type":"user","timestamp":"2026-10-27T10:00:00Z"}"#))
    }
}

final class UsageTests: XCTestCase {
    func testUnitsWeighModelsAndKinds() {
        let million = TokenCounts(input: 1_000_000)
        XCTAssertEqual(UsageMath.units(million, .haiku), 1, accuracy: 1e-9)
        XCTAssertEqual(UsageMath.units(million, .opus), 5, accuracy: 1e-9)
        XCTAssertEqual(UsageMath.units(TokenCounts(output: 1_000_000), .sonnet), 15, accuracy: 1e-9)
        XCTAssertEqual(UsageMath.units(TokenCounts(cacheRead: 1_000_000), .sonnet), 0.3, accuracy: 1e-9)

        var ledger = UsageLedger()
        ledger.add(million, .opus)
        ledger.add(million, .haiku)
        XCTAssertEqual(ledger.units, 6, accuracy: 1e-9)
        XCTAssertEqual(ledger.tokens, 2_000_000)
    }
}

final class GovernorTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: s)!
    }

    func governor(_ change: (inout BudgetSettings) -> Void = { _ in }) -> BudgetGovernor {
        var s = BudgetSettings()
        s.others = [:]
        change(&s)
        return BudgetGovernor(settings: s, calendar: calendar)
    }

    func testWeekStartsOnTheResetDay() {
        let g = governor() // Monday 00:00
        // 2026-10-28 is a Wednesday.
        XCTAssertEqual(g.weekStart(for: date("2026-10-28T15:00:00Z")), date("2026-10-26T00:00:00Z"))
        XCTAssertEqual(g.weekStart(for: date("2026-10-26T00:00:00Z")), date("2026-10-26T00:00:00Z"))
    }

    func testReadingFromMeasurementAndOthers() {
        let g = governor { $0.others = ["comet": 14]; $0.unitsPerPercent = 10 }
        let now = date("2026-10-29T12:00:00Z") // half a week after Monday 00:00
        let r = g.reading(now: now, macUnits: { _ in 100 }, cloudUnits: { _ in 50 }, zenithUnits: { _ in 80 })
        XCTAssertEqual(r.macPercent, 10, accuracy: 1e-9)
        XCTAssertEqual(r.cloudPercent, 5, accuracy: 1e-9)
        XCTAssertEqual(r.othersPercent, 7, accuracy: 1e-9)
        XCTAssertEqual(r.usedPercent, 22, accuracy: 1e-9)
        XCTAssertEqual(r.zenithPercent, 8, accuracy: 1e-9)
        XCTAssertFalse(r.calibrated)
        XCTAssertEqual(r.roomPercent, 28, accuracy: 1e-9)
    }

    func testCalibrationIsTheTruthFromItsMoment() {
        let cal = date("2026-10-28T00:00:00Z")
        let g = governor { $0.calibration = Calibration(at: cal, shownPercent: 30); $0.unitsPerPercent = 10 }
        let now = date("2026-10-28T12:00:00Z")
        let r = g.reading(now: now, macUnits: { since in since == cal ? 20 : 999 }, cloudUnits: { _ in 0 }, zenithUnits: { _ in 0 })
        XCTAssertTrue(r.calibrated)
        XCTAssertEqual(r.usedPercent, 32, accuracy: 1e-9)
    }

    func testCalibrationFromLastWeekIsIgnored() {
        let g = governor { $0.calibration = Calibration(at: self.date("2026-10-20T00:00:00Z"), shownPercent: 45) }
        let r = g.reading(now: date("2026-10-28T12:00:00Z"), macUnits: { _ in 0 }, cloudUnits: { _ in 0 }, zenithUnits: { _ in 0 })
        XCTAssertFalse(r.calibrated)
        XCTAssertEqual(r.usedPercent, 0, accuracy: 1e-9)
    }

    func reading(_ used: Double, _ g: BudgetGovernor) -> BudgetReading {
        BudgetReading(weekStart: date("2026-10-26T00:00:00Z"), weekEnd: date("2026-11-02T00:00:00Z"), macPercent: used,
                      cloudPercent: 0, zenithPercent: 0, othersPercent: 0, usedPercent: used, capPercent: g.settings.capPercent,
                      calibrated: false)
    }

    func testDecisions() {
        let g = governor { $0.preferOvernight = true; $0.heavyPercent = 5; $0.overnightStart = 1; $0.overnightEnd = 7 }
        let day = date("2026-10-28T14:00:00Z")
        let night = date("2026-10-28T02:00:00Z")

        XCTAssertEqual(g.decide(estimatePercent: 2, reading: reading(10, g), running: 0, now: day), .go)
        // Heavy work waits for the night, and goes when it's night.
        XCTAssertEqual(g.decide(estimatePercent: 8, reading: reading(10, g), running: 0, now: day), .waitForNight(date("2026-10-29T01:00:00Z")))
        XCTAssertEqual(g.decide(estimatePercent: 8, reading: reading(10, g), running: 0, now: night), .go)
        // Over the cap (less the margin) waits for room.
        if case .waitForRoom = g.decide(estimatePercent: 3, reading: reading(47, g), running: 0, now: day) {} else { XCTFail() }
        // Tight: a second mission queues behind the first.
        XCTAssertEqual(g.decide(estimatePercent: 4, reading: reading(42, g), running: 1, now: day), .waitForTurn)
        XCTAssertEqual(g.decide(estimatePercent: 4, reading: reading(42, g), running: 0, now: day), .go)
    }

    func testPausesBeforeTheCap() {
        let g = governor()
        XCTAssertFalse(g.mustPause(reading(48.9, g)))
        XCTAssertTrue(g.mustPause(reading(49, g)))
    }

    func testOvernightWindowWrapsMidnight() {
        let g = governor { $0.overnightStart = 23; $0.overnightEnd = 6 }
        XCTAssertTrue(g.isOvernight(date("2026-10-28T23:30:00Z")))
        XCTAssertTrue(g.isOvernight(date("2026-10-28T05:59:00Z")))
        XCTAssertFalse(g.isOvernight(date("2026-10-28T06:00:00Z")))
        XCTAssertEqual(g.nextOvernight(after: date("2026-10-28T12:00:00Z")), date("2026-10-28T23:00:00Z"))
    }
}

final class MissionTests: XCTestCase {
    func testColumnsFollowStatus() {
        var m = Mission(title: "x", brief: "y")
        XCTAssertEqual(m.column, .forecast)
        for (status, column) in [(MissionStatus.queued, BoardColumn.working), (.paused, .working), (.reviewing, .working),
                                 (.needsYou, .needsYou), (.failed, .done), (.living, .living)] {
            m.status = status
            XCTAssertEqual(m.column, column)
        }
    }

    func testAdoptForecast() {
        var m = Mission(title: "New mission", brief: "Do it")
        let f = Forecast(title: "Do it well", summary: "", steps: [.init(title: "A", detail: "", member: .cloud, model: .sonnet),
                                                                   .init(title: "B", detail: "", member: .nova, model: .haiku)],
                         hours: 1, usagePercent: 2, needsYou: [], assumptions: ["Assume X"])
        m.adopt(f)
        XCTAssertEqual(m.title, "Do it well")
        XCTAssertEqual(m.steps.count, 2)
        XCTAssertEqual(m.nextStep, 0)
        XCTAssertEqual(m.assumptions, ["Assume X"])
        m.steps[0].status = .done
        XCTAssertEqual(m.progress, 0.5)
        XCTAssertEqual(m.nextStep, 1)
        m.steps[1].status = .running
        m.status = .running
        XCTAssertEqual(m.activeMember, .nova)
    }

    func testStatusNeedsNoTokens() {
        var m = Mission(title: "Bakery site", brief: "")
        m.status = .needsYou
        m.steps = [Step(title: "Build", detail: "", member: .cloud, model: .sonnet)]
        m.steps[0].status = .done
        m.questions = [Question(stepID: nil, text: "Buy the domain?", kind: .yesNo)]
        XCTAssertEqual(Prompts.status([m]), "Bakery site: needs you, 1 of 1 steps done. 1 question waits for you in Zenith.")
        XCTAssertEqual(Prompts.status([]), "No missions running right now.")
    }

    func testDoneText() {
        var m = Mission(title: "Bakery site", brief: "")
        m.summary = "It's live."
        m.deliverables = ["site/", "https://bakery.vercel.app"]
        XCTAssertEqual(Prompts.doneText(m), "Zenith: Bakery site is done. It's live. https://bakery.vercel.app Everything is on the mission board.")
    }

    func testBriefFileHoldsAnswers() {
        var m = Mission(title: "T", brief: "Brief text")
        var q = Question(stepID: nil, text: "Color?", kind: .text)
        q.answer = "Blue"
        m.questions = [q]
        XCTAssertTrue(Prompts.briefFile(m).contains("- Color? → Blue"))
    }
}

final class AllowlistTests: XCTestCase {
    func testMatching() {
        let list = ["+1 (555) 123-4567", "sam@example.com", "Mom"]
        XCTAssertTrue(Allowlist.allows("5551234567", list: list))
        XCTAssertTrue(Allowlist.allows("+15551234567", list: list))
        XCTAssertTrue(Allowlist.allows("SAM@example.com", list: list))
        XCTAssertTrue(Allowlist.allows("mom", list: list))
        XCTAssertTrue(Allowlist.allows("me", list: []))
        XCTAssertTrue(Allowlist.allows(nil, list: []))
        XCTAssertFalse(Allowlist.allows("+15559999999", list: list))
        XCTAssertFalse(Allowlist.allows("Alex", list: list))
    }
}
