import Foundation
import ZenithCore

/// Runs missions: brief → forecast → one thumbs up → work → needs you → self-check → done
/// (→ living). The budget governor decides when anything may start, and every tick it
/// checks the Galaxy is still under its cap.
@MainActor
final class Commander: ObservableObject {
    static let shared = Commander()

    struct LiveLine: Equatable {
        var member: Member
        var text: String
        var at: Date
    }

    enum CloudCheck: Equatable {
        case idle, checking, passed, failed(String)
    }

    let store = Store.shared
    @Published private(set) var reading: BudgetReading?
    /// What each running mission is doing this second.
    @Published private(set) var live: [String: LiveLine] = [:]
    @Published var cloudCheck: CloudCheck = .idle

    private var drivers: [String: Task<Void, Never>] = [:]
    private var workers: [String: ClaudeCode] = [:]
    private var approvalWatchers: [String: Task<Void, Never>] = [:]
    private var timer: Timer?
    private let link = GalaxyLink.shared

    var governor: BudgetGovernor { BudgetGovernor(settings: store.settings.budget) }
    private var useCloud: Bool { store.settings.backend == .cloud && store.settings.cloudVerifiedAt != nil }

    // MARK: - Start

    func start() {
        // Missions a quit interrupted pick up where they were.
        for m in store.missions {
            switch m.status {
            case .running, .reviewing:
                store.update(m.id) { m in
                    m.status = .queued
                    m.statusNote = "Picking up where it left off"
                    for i in m.steps.indices where m.steps[i].status == .running { m.steps[i].status = .pending }
                }
            case .forecasting:
                forecast(m.id)
            case .awaitingLaunch:
                requestLaunchApproval(m.id)
            case .needsYou:
                armApprovals(m.id)
            default:
                break
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
        Task { await tick(force: true) }
    }

    func shutdown() {
        for (_, w) in workers { w.cancel() }
        store.flush()
    }

    /// Every 30 seconds: measure, pause before the cap, start what may start, keep living missions alive.
    func tick(force: Bool = false) async {
        await refreshBudget(force: force)
        store.flush()
        guard let reading else { return }
        let gov = governor
        let now = Date()

        if gov.mustPause(reading) {
            for m in store.missions where m.status == .running {
                budgetPause(m.id, reading: reading)
            }
            return
        }

        var running = store.missions.filter { $0.isActive }.count
        let queued = store.missions.filter { $0.status == .queued }
            .sorted { ($0.launchedAt ?? $0.createdAt) < ($1.launchedAt ?? $1.createdAt) }
        for m in queued {
            let decision = gov.decide(estimatePercent: remainingEstimate(m), reading: reading, running: running, now: now)
            var note = ""
            switch decision {
            case .go where running < store.settings.maxParallel:
                begin(m.id)
                running += 1
                continue
            case .go:
                note = "Queued behind \(running) running \(running == 1 ? "mission" : "missions")"
            case .waitForTurn:
                note = "Usage is tight, so it runs after the mission in front of it"
            case .waitForNight(let at):
                note = "Heavy work: starts in the overnight window, \(Format.date(at))"
            case .waitForRoom(let why):
                note = why
            }
            if m.statusNote != note { store.update(m.id) { $0.statusNote = note } }
        }

        for m in store.missions where m.status == .living && drivers[m.id] == nil {
            guard let plan = m.living, plan.enabled, plan.nextRun <= now else { continue }
            if case .go = gov.decide(estimatePercent: 0.5, reading: reading, running: 0, now: now) {
                runLiving(m.id)
            }
        }
    }

    private func remainingEstimate(_ m: Mission) -> Double {
        max(0.5, (m.forecast?.usagePercent ?? 2) * (1 - m.progress))
    }

    func refreshBudget(force: Bool = false) async {
        await UsageMeter.shared.scan(force: force)
        let gov = governor
        let now = Date()
        let entries = await UsageMeter.shared.entries(since: gov.weekStart(for: now))
        let runs = store.runs
        reading = gov.reading(
            now: now,
            macUnits: { since in entries.filter { $0.at >= since }.reduce(0) { $0 + UsageMath.units($1.counts, $1.model) } },
            cloudUnits: { since in runs.filter { $0.cloud && $0.at >= since }.reduce(0) { $0 + $1.units } },
            zenithUnits: { since in runs.filter { $0.at >= since }.reduce(0) { $0 + $1.units } })
    }

    /// Calibrates the meter to what Claude's usage page shows right now.
    func calibrate(shownPercent: Double) {
        store.settings.budget.calibration = Calibration(at: Date(), shownPercent: shownPercent)
        Task { await refreshBudget(force: true) }
    }

    /// What the governor would do with a forecast right now, in words.
    func launchPreview(_ m: Mission) -> String {
        guard let reading, let f = m.forecast else { return "" }
        let running = store.missions.filter { $0.isActive }.count
        switch governor.decide(estimatePercent: f.usagePercent, reading: reading, running: running, now: Date()) {
        case .go: return "Starts as soon as you launch it."
        case .waitForTurn: return "Usage is tight, so it starts after the running mission."
        case .waitForNight(let at): return "Heavy work: it waits for the overnight window, \(Format.date(at))."
        case .waitForRoom(let why): return why
        }
    }

    // MARK: - Brief and forecast

    @discardableResult
    func create(brief: String, context: String = "", source: MissionSource = .app, linkTaskID: String? = nil) -> String {
        var m = Mission(title: "New mission", brief: brief.trimmingCharacters(in: .whitespacesAndNewlines),
                        context: context, source: source)
        m.linkTaskID = linkTaskID
        m.log(.zenith, .note, "Brief from \(source.title)")
        store.add(m)
        forecast(m.id)
        return m.id
    }

    func forecast(_ id: String) {
        guard drivers[id] == nil else { return }
        store.update(id) { $0.status = .forecasting; $0.statusNote = "" }
        drivers[id] = Task {
            await runForecast(id)
            drivers[id] = nil
        }
    }

    private func runForecast(_ id: String) async {
        guard let m = store.mission(id) else { return }
        setLive(id, .zenith, "Writing the forecast")
        let galaxy = await link.promptContext() ?? ""
        let prompt = Prompts.forecast(brief: m.brief, context: m.context, galaxy: galaxy,
                                      allowlist: store.settings.allowlist, now: Date())
        do {
            let request = ClaudeRequest(prompt: prompt, model: .opus, directory: store.workspace(id), tools: [],
                                        sandboxed: store.settings.sandboxed)
            let result = try await claude(id, request, member: .zenith, quiet: true)
            guard let f = Forecast.parse(result.text) else {
                throw ClaudeError.failed("The forecast didn't come back in a form Zenith can read. Try forecasting again.")
            }
            store.update(id) { m in
                m.adopt(f)
                m.status = .awaitingLaunch
                m.statusNote = ""
                m.log(.zenith, .plan, "Forecast: \(f.steps.count) \(f.steps.count == 1 ? "step" : "steps"), about \(Format.hours(f.hours)), \(Format.percent(f.usagePercent)) of the week")
            }
            clearLive(id)
            if let task = m.linkTaskID {
                await link.progress(task, note: "Forecast ready: \(f.title). It launches with one thumbs up.")
            }
            requestLaunchApproval(id)
        } catch {
            clearLive(id)
            store.update(id) { m in
                m.status = .failed
                m.statusNote = error.localizedDescription
                m.log(.zenith, .error, "Forecast failed: \(error.localizedDescription)")
            }
            if let task = m.linkTaskID { await link.finish(task, ok: false, result: "Zenith couldn't forecast it: \(error.localizedDescription)") }
        }
    }

    // MARK: - Launch and control

    /// The thumbs up.
    func launch(_ id: String) {
        guard let m = store.mission(id), m.status == .awaitingLaunch else { return }
        cancelApproval(id)
        store.update(id) { m in
            m.status = .queued
            m.launchedAt = Date()
            m.statusNote = "Starting"
            m.onCloud = useCloud
            m.log(.zenith, .plan, "Launched")
        }
        Task {
            await link.note("Launched the mission \"\(m.title)\"")
            await tick()
        }
    }

    /// Thumbs down on a forecast.
    func decline(_ id: String) {
        cancelApproval(id)
        store.update(id) { m in
            m.status = .stopped
            m.statusNote = "Not launched"
            m.finishedAt = Date()
            m.log(.zenith, .note, "Not launched")
        }
        if let task = store.mission(id)?.linkTaskID { Task { await link.finish(task, ok: false, result: "Not launched.") } }
    }

    private func begin(_ id: String) {
        guard drivers[id] == nil else { return }
        store.update(id) { m in
            m.status = .running
            m.statusNote = ""
        }
        drivers[id] = Task {
            await drive(id)
            drivers[id] = nil
        }
    }

    func pause(_ id: String) {
        halt(id)
        store.update(id) { m in
            m.status = .paused
            m.statusNote = "Paused by you"
            for i in m.steps.indices where m.steps[i].status == .running { m.steps[i].status = .pending }
            m.log(.zenith, .note, "Paused")
        }
    }

    func resume(_ id: String) {
        store.update(id) { m in
            m.status = .queued
            m.statusNote = "Resuming"
            m.log(.zenith, .note, "Resumed")
        }
        Task { await tick() }
    }

    /// Changes course: the step in flight restarts with the new direction first.
    func redirect(_ id: String, _ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let m = store.mission(id) else { return }
        let wasRunning = m.status == .running
        if wasRunning { halt(id) }
        store.update(id) { m in
            m.redirect = clean
            m.log(.zenith, .note, "Change of course: \(clean)")
            for i in m.steps.indices where m.steps[i].status == .running { m.steps[i].status = .pending }
            if wasRunning { m.status = .queued }
        }
        if wasRunning { Task { await tick() } }
    }

    func stop(_ id: String) {
        halt(id)
        cancelApproval(id)
        guard let m = store.mission(id) else { return }
        for step in m.steps where step.status == .waiting {
            if let t = step.linkTaskID { Task { await link.cancel(task: t) } }
        }
        store.update(id) { m in
            m.status = .stopped
            m.statusNote = "Stopped by you"
            m.finishedAt = Date()
            for i in m.steps.indices where [.running, .waiting, .pending].contains(m.steps[i].status) { m.steps[i].status = .skipped }
            m.log(.zenith, .note, "Stopped")
        }
        if let task = m.linkTaskID { Task { await link.finish(task, ok: false, result: "Stopped by the user.") } }
    }

    func delete(_ id: String) {
        if let m = store.mission(id), !m.isFinished { stop(id) }
        halt(id)
        store.delete(id)
    }

    private func halt(_ id: String) {
        workers[id]?.cancel()
        drivers[id]?.cancel()
        drivers[id] = nil
        clearLive(id)
    }

    private func budgetPause(_ id: String, reading: BudgetReading) {
        halt(id)
        store.update(id) { m in
            m.status = .queued
            m.statusNote = "Paused before the \(Int(reading.capPercent))% cap. It picks up when there's room."
            for i in m.steps.indices where m.steps[i].status == .running { m.steps[i].status = .pending }
            m.log(.zenith, .budget, String(format: "Paused at %.0f%% of the week, before the %.0f%% cap", reading.usedPercent, reading.capPercent))
        }
    }

    // MARK: - The work

    private func drive(_ id: String) async {
        while !Task.isCancelled {
            guard let m = store.mission(id), m.status == .running else { return }
            if let reading, governor.mustPause(reading) {
                budgetPause(id, reading: reading)
                return
            }
            // A handoff still out with Nova or Comet (after a restart): keep waiting on it.
            if let w = m.steps.firstIndex(where: { s in
                s.status == .waiting && s.linkTaskID != nil && !m.openQuestions.contains { $0.stepID == s.id }
            }) {
                await waitForLinkTask(id, w)
                continue
            }
            if let i = m.nextStep {
                await runStep(id, i)
                continue
            }
            if !m.openQuestions.isEmpty {
                needsYou(id)
                return
            }
            if m.steps.contains(where: { $0.status == .waiting }) {
                // Waiting with nothing to ask: shouldn't happen, but never spin.
                return
            }
            await review(id)
            if store.mission(id)?.nextStep != nil { continue }
            await finish(id)
            return
        }
    }

    private func runStep(_ id: String, _ i: Int) async {
        guard var step = store.mission(id)?.steps[i] else { return }
        store.update(id) { m in
            m.steps[i].status = .running
            m.steps[i].startedAt = Date()
            m.log(step.member == .zenith ? .cloud : step.member, .step, "Started: \(step.title)")
        }
        step = store.mission(id)!.steps[i]
        switch step.member {
        case .nova, .comet:
            await runLinkStep(id, i)
        default:
            await runCloudStep(id, i)
        }
    }

    private func runCloudStep(_ id: String, _ i: Int) async {
        guard let m = store.mission(id) else { return }
        let step = m.steps[i]
        let cloud = useCloud
        writeBriefing(id)

        var prompt: String
        var resume: String?
        if step.followUp, let session = step.sessionID, !cloud {
            prompt = step.detail
            resume = session
        } else {
            prompt = step.followUp ? step.detail : Prompts.step(step, number: i + 1, of: m.steps.count, redirect: m.redirect)
        }
        if cloud {
            // A cloud session can't see the Mac's workspace: it gets the brief and log inline.
            prompt = Prompts.briefFile(m) + "\n" + Prompts.logFile(m) + "\n---\n\n" + prompt
        }
        let system = Prompts.worker + (cloud ? Self.cloudNote : "")

        var lastError = ""
        for attempt in 0..<2 {
            setLive(id, .cloud, attempt == 0 ? "Starting: \(step.title)" : "Trying again: \(step.title)")
            do {
                let request = ClaudeRequest(prompt: prompt, model: step.model, directory: store.workspace(id),
                                            appendSystemPrompt: system, tools: nil, resume: resume, cloud: cloud,
                                            sandboxed: store.settings.sandboxed)
                let result = try await claude(id, request, member: .cloud)
                apply(StepReport.parse(result.text), session: result.sessionID, to: id, step: i)
                return
            } catch ClaudeError.cancelled {
                return
            } catch {
                lastError = error.localizedDescription
                if Task.isCancelled { return }
                store.update(id) { $0.log(.cloud, .error, "\(step.title): \(lastError)") }
                resume = nil
            }
        }
        clearLive(id)
        store.update(id) { m in
            m.steps[i].status = .failed
            m.steps[i].finishedAt = Date()
            m.steps[i].summary = lastError
            m.status = .failed
            m.statusNote = "\(step.title) failed twice: \(lastError)"
        }
        if let task = m.linkTaskID { await link.finish(task, ok: false, result: "Zenith stopped on a problem: \(lastError)") }
    }

    static let cloudNote = """


    You are in a Claude Code cloud session: your workspace is in the cloud, not on the user's Mac, and the brief and \
    log are in this prompt instead of files. Deliver by deploying, pushing to a repository, or another link the user \
    can open, and list those links as deliverables. Snapshots can't reach the Mac from here; skip them.
    """

    /// Takes in what a step reported: its summary, assumptions, questions, deliverables,
    /// snapshots, the handoffs it asked for, and any new skill it built.
    private func apply(_ report: StepReport, session: String, to id: String, step i: Int) {
        guard let m = store.mission(id) else { return }
        let step = m.steps[i]
        let settings = store.settings
        var snapshotEvents: [TimelineEvent] = []
        if !m.onCloud {
            for (n, path) in report.snapshots.prefix(12).enumerated() {
                let source = store.workspace(id).appendingPathComponent(path)
                let name = "\(step.id)-\(n).\(source.pathExtension.isEmpty ? "png" : source.pathExtension)"
                let target = store.snapshots(id).appendingPathComponent(name)
                try? FileManager.default.removeItem(at: target)
                if (try? FileManager.default.copyItem(at: source, to: target)) != nil {
                    snapshotEvents.append(TimelineEvent(member: .cloud, kind: .snapshot, text: source.lastPathComponent, file: name))
                }
            }
        }

        store.update(id) { m in
            m.steps[i].status = .done
            m.steps[i].finishedAt = Date()
            m.steps[i].summary = report.summary
            if !session.isEmpty { m.steps[i].sessionID = session }
            m.redirect = nil
            m.assume(report.assumptions)
            for d in report.deliverables where !m.deliverables.contains(d) { m.deliverables.append(d) }
            m.log(.cloud, .step, "Finished: \(step.title). \(report.summary)")
            m.timeline += snapshotEvents

            for ask in report.questions {
                m.questions.append(Question(stepID: step.id, text: ask.text, kind: ask.kind, options: ask.options, reason: ask.reason))
                m.log(.cloud, .question, ask.text)
            }

            var insertAt = i + 1
            for h in report.handoffs {
                var s = Step(title: h.title, detail: h.instructions, member: h.member, model: .haiku)
                s.recipient = h.recipient
                let allowed = h.member == .nova ? settings.useNova : settings.useComet
                if !allowed {
                    s.status = .skipped
                    s.summary = "\(h.member.name) is turned off for missions in Settings."
                } else if h.member == .comet, !Allowlist.allows(h.recipient, list: settings.allowlist) {
                    s.status = .waiting
                    m.questions.append(Question(stepID: s.id, text: "Let Comet text \(h.recipient ?? "them")? \(h.title): \(h.instructions)",
                                                kind: .yesNo, reason: .contact))
                }
                m.steps.insert(s, at: insertAt)
                insertAt += 1
                m.log(.cloud, .handoff, "Asked for \(h.member.name): \(h.title)")
            }

            if var skill = report.skill, !m.skills.contains(where: { $0.name == skill.name }) {
                skill.installed = false
                m.skills.append(skill)
                m.questions.append(Question(stepID: nil, text: "Install the new skill \"\(skill.name)\" into \(skill.target.name) for good? \(skill.summary)",
                                            kind: .yesNo, reason: .install, skill: skill))
                m.log(.cloud, .note, "Built and tested a new skill: \(skill.name)")
            }
        }
        clearLive(id)
    }

    private func runLinkStep(_ id: String, _ i: Int) async {
        guard let m = store.mission(id) else { return }
        let step = m.steps[i]
        let settings = store.settings
        let allowed = step.member == .nova ? settings.useNova : settings.useComet
        guard allowed else {
            store.update(id) { m in
                m.steps[i].status = .skipped
                m.steps[i].summary = "\(step.member.name) is turned off for missions in Settings."
                m.log(.zenith, .note, "Skipped \(step.title): \(step.member.name) is off for missions")
            }
            return
        }
        var detail = step.detail
        if step.member == .comet {
            let list = settings.allowlist.isEmpty ? "only the user" : "the user and \(settings.allowlist.joined(separator: ", "))"
            detail += "\n\nYou may text \(list) without asking. Anyone else needs the user's thumbs up first: don't text them; say so in your result."
        }
        let instructions = step.member == .nova
            ? Prompts.forNova(detail, mission: m.title)
            : Prompts.forComet(detail, recipient: step.recipient, mission: m.title)
        let power = step.member == .nova ? "screen" : "imessage"
        guard let task = await link.handoff(to: step.member.rawValue, power: power, title: step.title,
                                            instructions: instructions, replyTo: id) else {
            store.update(id) { m in
                m.steps[i].status = .waiting
                m.questions.append(Question(stepID: step.id,
                                            text: "Galaxy Link isn't running, so \(step.member.name) couldn't take \"\(step.title)\". Start Link and try again, or skip it?",
                                            kind: .choice, options: ["Try again", "Skip it"]))
                m.log(.zenith, .error, "Couldn't reach \(step.member.name) through Galaxy Link")
            }
            return
        }
        store.update(id) { m in
            m.steps[i].status = .waiting
            m.steps[i].linkTaskID = task.id
            m.log(step.member, .handoff, "Handed to \(step.member.name): \(step.title)")
        }
        await waitForLinkTask(id, i)
    }

    private func waitForLinkTask(_ id: String, _ i: Int) async {
        guard let step = store.mission(id)?.steps[i], let taskID = step.linkTaskID else { return }
        setLive(id, step.member, "\(step.member.name) is on it: \(step.title)")
        while !Task.isCancelled {
            guard let m = store.mission(id), m.status == .running else { return }
            if let task = await link.task(taskID), ["done", "failed", "cancelled"].contains(task.status) {
                let ok = task.status == "done"
                let result = task.result.isEmpty ? (ok ? "Done." : "Couldn't finish.") : task.result
                store.update(id) { m in
                    m.steps[i].status = ok ? .done : .failed
                    m.steps[i].finishedAt = Date()
                    m.steps[i].summary = result
                    m.log(step.member, .message, "\(ok ? "Finished" : "Couldn't finish"): \(step.title). \(String(result.prefix(400)))")
                }
                clearLive(id)
                return
            }
            try? await Task.sleep(for: .seconds(10))
        }
    }

    // MARK: - Needs you

    private func needsYou(_ id: String) {
        clearLive(id)
        guard let m = store.update(id, { x in
            let n = x.openQuestions.count
            x.status = .needsYou
            x.statusNote = "\(n) \(n == 1 ? "question" : "questions")"
            x.log(.zenith, .question, "Everything else is done. \(n) \(n == 1 ? "question waits" : "questions wait") for you.")
        }) else { return }
        if let task = m.linkTaskID { Task { await link.progress(task, note: "\(m.openQuestions.count) questions wait in Zenith.") } }
        armApprovals(id)
    }

    func answer(_ id: String, question qid: String, _ text: String) {
        store.update(id) { m in
            if let q = m.questions.firstIndex(where: { $0.id == qid }) { m.questions[q].answer = text }
        }
    }

    /// The batch is answered: act on every answer and get back to work.
    func submitAnswers(_ id: String) {
        guard let m = store.mission(id), m.openQuestions.isEmpty else { return }
        cancelApproval(id)
        var followUps: [String: [Question]] = [:]
        var installs: [SkillProposal] = []
        store.update(id) { m in
            for q in m.questions.indices where !m.questions[q].applied && m.questions[q].isAnswered {
                let question = m.questions[q]
                m.questions[q].applied = true
                m.log(.zenith, .answer, "\(question.text) → \(question.answer ?? "")")
                if question.reason == .install, let skill = question.skill {
                    if question.approved { installs.append(skill) }
                    continue
                }
                guard let sid = question.stepID, let s = m.steps.firstIndex(where: { $0.id == sid }) else { continue }
                switch m.steps[s].status {
                case .waiting:
                    let a = (question.answer ?? "").lowercased()
                    let go = a == "yes" || a == "try again"
                    m.steps[s].status = go ? .pending : .skipped
                    if go { m.steps[s].linkTaskID = nil } else { m.steps[s].summary = "Skipped: \(question.answer ?? "")" }
                case .done where m.steps[s].member == .cloud:
                    followUps[sid, default: []].append(question)
                default:
                    break
                }
            }
            // Each step that asked something finishes with its answers, in its own session.
            for (sid, qs) in followUps {
                guard let s = m.steps.firstIndex(where: { $0.id == sid }) else { continue }
                let original = m.steps[s]
                var f = Step(title: "Finish \"\(original.title)\" with your answers", detail: Prompts.answers(qs),
                             member: .cloud, model: original.model)
                f.followUp = true
                f.sessionID = original.sessionID
                m.steps.insert(f, at: s + 1)
            }
            m.status = .queued
            m.statusNote = "Answers in, picking back up"
        }
        for skill in installs { install(skill, from: id) }
        Task { await tick() }
    }

    /// Nebula's thumbs up or down: one yes-or-no question at a time, answered by hand.
    private func armApprovals(_ id: String) {
        guard store.settings.nebulaApprovals, approvalWatchers[id] == nil,
              let m = store.mission(id), m.status == .needsYou,
              let q = m.openQuestions.first(where: { $0.kind == .yesNo }) else { return }
        approvalWatchers[id] = Task {
            let decision = await awaitDecision(id, title: String(q.text.prefix(200)), detail: "Zenith: \(m.title)")
            approvalWatchers[id] = nil
            guard let decision, !Task.isCancelled else { return }
            answer(id, question: q.id, decision ? "Yes" : "No")
            store.update(id) { $0.log(.nebula, .answer, "\(decision ? "Thumbs up" : "Thumbs down"): \(q.text)") }
            if store.mission(id)?.openQuestions.isEmpty == true {
                submitAnswers(id)
            } else {
                armApprovals(id)
            }
        }
    }

    private func requestLaunchApproval(_ id: String) {
        guard store.settings.nebulaApprovals, approvalWatchers[id] == nil,
              let m = store.mission(id), m.status == .awaitingLaunch, let f = m.forecast else { return }
        approvalWatchers[id] = Task {
            let title = "Launch \"\(f.title)\"? About \(Format.hours(f.hours)) and \(Format.percent(f.usagePercent)) of the week."
            let decision = await awaitDecision(id, title: title, detail: f.summary)
            approvalWatchers[id] = nil
            guard let decision, !Task.isCancelled, store.mission(id)?.status == .awaitingLaunch else { return }
            if decision {
                store.update(id) { $0.log(.nebula, .answer, "Thumbs up: launch") }
                launch(id)
            } else {
                decline(id)
            }
        }
    }

    /// Asks Galaxy Link for a yes or no (Nebula arms its camera for it) and waits for the
    /// answer. nil when there's no answer to be had: no Link, no approvals API, or it expired.
    private func awaitDecision(_ id: String, title: String, detail: String) async -> Bool? {
        guard let approval = await link.requestApproval(title: title, detail: detail, ttlSeconds: 3600) else { return nil }
        store.update(id) { $0.linkApprovalID = approval.id }
        var misses = 0
        while !Task.isCancelled {
            guard let now = await link.waitForApproval(approval.id) else {
                misses += 1
                if misses >= 4 { break }
                try? await Task.sleep(for: .seconds(15))
                continue
            }
            misses = 0
            if now.status == "pending" { continue }
            store.update(id) { $0.linkApprovalID = nil }
            return now.status == "approved" ? true : (now.status == "rejected" ? false : nil)
        }
        return nil
    }

    private func cancelApproval(_ id: String) {
        approvalWatchers[id]?.cancel()
        approvalWatchers[id] = nil
        if let a = store.mission(id)?.linkApprovalID {
            store.update(id) { $0.linkApprovalID = nil }
            Task { await link.cancel(approval: a) }
        }
    }

    // MARK: - Self-check and done

    private func review(_ id: String) async {
        guard let m = store.mission(id) else { return }
        store.update(id) { m in
            m.status = .reviewing
            m.log(.zenith, .review, "Checking the work against the brief")
        }
        writeBriefing(id)
        setLive(id, .zenith, "Checking the work against the brief")
        do {
            var prompt = Prompts.review
            if m.onCloud { prompt = Prompts.briefFile(m) + "\n" + Prompts.logFile(m) + "\n---\n\n" + prompt }
            let request = ClaudeRequest(prompt: prompt, model: .opus, directory: store.workspace(id),
                                        appendSystemPrompt: Prompts.reviewer + (m.onCloud ? Self.cloudNote : ""),
                                        tools: ["Read", "Glob", "Grep", "Bash", "WebFetch", "WebSearch"],
                                        cloud: m.onCloud, sandboxed: store.settings.sandboxed)
            let result = try await claude(id, request, member: .zenith)
            let verdict = ReviewReport.parse(result.text)
            store.update(id) { m in
                m.review = verdict
                m.status = .running
                if verdict.pass {
                    m.log(.zenith, .review, "Passed: \(verdict.summary)")
                } else if m.fixRounds < 1 {
                    m.fixRounds += 1
                    m.log(.zenith, .review, "Sent back: \(verdict.issues.joined(separator: "; "))")
                    m.steps.append(Step(title: "Fix what the review found", detail: Prompts.fix(verdict.issues), member: .cloud, model: .sonnet))
                } else {
                    m.log(.zenith, .review, "Still has issues after a fix round: \(verdict.issues.joined(separator: "; "))")
                }
            }
        } catch ClaudeError.cancelled {
            return
        } catch {
            store.update(id) { m in
                m.status = .running
                m.log(.zenith, .error, "The review couldn't run: \(error.localizedDescription)")
            }
        }
        clearLive(id)
    }

    private func finish(_ id: String) async {
        guard let before = store.mission(id), before.status == .running else { return }
        let fallback = before.steps.last(where: { $0.status == .done && $0.member == .cloud })?.summary ?? ""
        guard let m = store.update(id, { x in
            let review = x.review?.summary ?? ""
            x.summary = review.isEmpty ? fallback : review
            x.finishedAt = Date()
            x.statusNote = ""
            if let task = x.forecast?.living {
                let cadence = x.forecast?.cadence ?? .daily
                x.living = LivingPlan(task: task, cadence: cadence, nextRun: Date().addingTimeInterval(cadence.interval))
                x.status = .living
                x.log(.zenith, .done, "Done, and living: \(task) (\(cadence.title.lowercased()))")
            } else {
                x.status = .done
                x.log(.zenith, .done, "Done")
            }
        }) else { return }
        clearLive(id)
        let text = Prompts.doneText(m)
        if let task = m.linkTaskID {
            // Link delivers the result to wherever the user is: that's the one done text.
            await link.finish(task, ok: true, result: text)
        } else if store.settings.doneText {
            _ = await link.handoff(to: "comet", power: "imessage", title: "Zenith: \(m.title) is done",
                                   instructions: "Text the user exactly this, and nothing else:\n\n\(text)", replyTo: id)
        }
        await link.note("Finished the mission \"\(m.title)\"", detail: m.summary)
    }

    // MARK: - Living

    func runLiving(_ id: String) {
        guard drivers[id] == nil else { return }
        drivers[id] = Task {
            await living(id)
            drivers[id] = nil
        }
    }

    private func living(_ id: String) async {
        guard let m = store.mission(id), let plan = m.living else { return }
        writeBriefing(id)
        setLive(id, .cloud, "Upkeep: \(plan.task)")
        var prompt = Prompts.living(plan, mission: m)
        if m.onCloud { prompt = Prompts.briefFile(m) + "\n" + Prompts.logFile(m) + "\n---\n\n" + prompt }
        let request = ClaudeRequest(prompt: prompt, model: .sonnet, directory: store.workspace(id),
                                    appendSystemPrompt: Prompts.worker + (m.onCloud ? Self.cloudNote : ""),
                                    cloud: m.onCloud, sandboxed: store.settings.sandboxed)
        do {
            let result = try await claude(id, request, member: .cloud, quiet: true)
            let report = StepReport.parse(result.text)
            store.update(id) { m in
                m.living?.runs.append(LivingRun(at: Date(), ok: true, note: report.summary, units: result.usage?.units ?? 0))
                m.living?.scheduleNext(from: Date())
                m.log(.cloud, .living, "Upkeep: \(report.summary)")
                // Living missions never ping: anything they need waits on the board.
                for ask in report.questions {
                    m.questions.append(Question(stepID: nil, text: ask.text, kind: ask.kind, options: ask.options, reason: ask.reason))
                }
                for d in report.deliverables where !m.deliverables.contains(d) { m.deliverables.append(d) }
            }
        } catch ClaudeError.cancelled {
        } catch {
            store.update(id) { m in
                m.living?.runs.append(LivingRun(at: Date(), ok: false, note: error.localizedDescription, units: 0))
                m.living?.scheduleNext(from: Date())
                m.log(.cloud, .error, "Upkeep failed: \(error.localizedDescription)")
            }
        }
        clearLive(id)
    }

    func setLiving(_ id: String, enabled: Bool? = nil, cadence: Cadence? = nil) {
        store.update(id) { m in
            if let enabled { m.living?.enabled = enabled }
            if let cadence, var plan = m.living {
                plan.cadence = cadence
                plan.scheduleNext(from: plan.runs.last?.at ?? Date())
                m.living = plan
            }
        }
    }

    /// Answers a living mission's own questions (they don't restart anything).
    func settleLivingQuestions(_ id: String) {
        store.update(id) { m in
            for q in m.questions.indices where m.questions[q].isAnswered && !m.questions[q].applied {
                m.questions[q].applied = true
                m.log(.zenith, .answer, "\(m.questions[q].text) → \(m.questions[q].answer ?? "")")
            }
        }
    }

    // MARK: - Self-upgrading Galaxy

    /// Installs a skill the cloud computer built, after the user's thumbs up: into Claude
    /// Code's skills for Zenith (so every future run has it), or handed to Comet or Nova.
    private func install(_ skill: SkillProposal, from id: String) {
        let source = store.workspace(id).appendingPathComponent(skill.path, isDirectory: true)
        let fm = FileManager.default
        var note: String
        switch skill.target {
        case .comet, .nova:
            var files: [String] = []
            var budget = 24_000
            if let walker = fm.enumerator(at: source, includingPropertiesForKeys: nil) {
                for case let url as URL in walker {
                    guard let text = try? String(contentsOf: url, encoding: .utf8), text.count < budget else { continue }
                    budget -= text.count
                    let rel = url.path.replacingOccurrences(of: source.path + "/", with: "")
                    files.append("--- \(rel)\n\(text)")
                }
            }
            if files.isEmpty {
                note = "Couldn't read the skill's files to send to \(skill.target.name)"
            } else {
                let instructions = "Install this Claude Code skill for good, as ~/.claude/skills/\(skill.name)/ (create each file exactly as given), then confirm it loads.\n\n\(skill.summary)\n\n" + files.joined(separator: "\n\n")
                Task {
                    _ = await link.handoff(to: skill.target.rawValue, power: skill.target == .nova ? "shell" : "code",
                                           title: "Install the skill \(skill.name)", instructions: instructions, replyTo: id)
                }
                note = "Sent \(skill.name) to \(skill.target.name) to install"
            }
        default:
            let target = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills/\(skill.name)", isDirectory: true)
            try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: target)
            do {
                try fm.copyItem(at: source, to: target)
                note = "Installed \(skill.name) for Zenith"
            } catch {
                note = "Couldn't install \(skill.name): \(error.localizedDescription)"
            }
        }
        store.update(id) { m in
            if let s = m.skills.firstIndex(where: { $0.name == skill.name }) { m.skills[s].installed = !note.hasPrefix("Couldn't") }
            m.log(.zenith, .note, note)
        }
    }

    // MARK: - Cloud check

    /// Proves Claude Code cloud sessions can be launched and read back from this Mac before
    /// Zenith trusts a mission to them.
    func verifyCloud() {
        guard cloudCheck != .checking else { return }
        cloudCheck = .checking
        let path = store.settings.claudePath
        let dir = store.dir.appendingPathComponent("cloud-check", isDirectory: true)
        Task {
            let worker = ClaudeCode()
            let timeout = Task {
                try? await Task.sleep(for: .seconds(300))
                worker.cancel()
            }
            defer { timeout.cancel() }
            do {
                let request = ClaudeRequest(prompt: "Reply with exactly this and nothing else: ZENITH-CLOUD-OK", model: .haiku,
                                            directory: dir, tools: [], cloud: true, sandboxed: false)
                let result = try await worker.run(request, claudePath: path) { _ in }
                if result.text.contains("ZENITH-CLOUD-OK") {
                    store.settings.cloudVerifiedAt = Date()
                    cloudCheck = .passed
                } else {
                    cloudCheck = .failed("A cloud session started but its answer didn't come back to the Mac.")
                }
            } catch ClaudeError.cancelled {
                cloudCheck = .failed("No answer from a cloud session within five minutes.")
            } catch {
                cloudCheck = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Plumbing

    private func claude(_ id: String, _ request: ClaudeRequest, member: Member, quiet: Bool = false) async throws -> RunResult {
        let worker = ClaudeCode()
        workers[id] = worker
        defer { workers[id] = nil }
        let result = try await worker.run(request, claudePath: store.settings.claudePath) { [weak self] event in
            Task { @MainActor in self?.handle(event, id: id, member: member, quiet: quiet) }
        }
        let ledger = result.usage ?? UsageLedger()
        store.update(id) { $0.usage.add(ledger) }
        store.record(ledger.units, cloud: request.cloud)
        Task { await refreshBudget(force: true) }
        guard result.ok else { throw ClaudeError.failed(result.error ?? "Claude Code reported an error.") }
        return result
    }

    private func handle(_ event: StreamEvent, id: String, member: Member, quiet: Bool) {
        switch event {
        case .tool(_, let summary):
            setLive(id, member, summary)
            if !quiet { store.update(id, persist: false) { $0.log(member, .tool, summary) } }
        case .text(let text):
            let line = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
            if !line.isEmpty && !line.hasPrefix("{") && !line.hasPrefix("```") { setLive(id, member, String(line.prefix(160))) }
        default:
            break
        }
    }

    private func setLive(_ id: String, _ member: Member, _ text: String) {
        live[id] = LiveLine(member: member, text: text, at: Date())
    }

    private func clearLive(_ id: String) {
        live[id] = nil
    }

    private func writeBriefing(_ id: String) {
        guard let m = store.mission(id) else { return }
        let dir = store.workspace(id).appendingPathComponent(".zenith", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("snapshots"), withIntermediateDirectories: true)
        try? Prompts.briefFile(m).write(to: dir.appendingPathComponent("BRIEF.md"), atomically: true, encoding: .utf8)
        try? Prompts.logFile(m).write(to: dir.appendingPathComponent("LOG.md"), atomically: true, encoding: .utf8)
    }
}
