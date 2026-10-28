import Foundation

/// Everything Zenith says to Claude. Kept short on purpose: the brief lives in the
/// workspace (.zenith/BRIEF.md) and every step reads it from there instead of carrying
/// it in its prompt, and follow-ups resume their session instead of starting over.
public enum Prompts {
    // MARK: - Forecast (Opus, no tools)

    public static func forecast(brief: String, context: String, galaxy: String, allowlist: [String], now: Date) -> String {
        """
        You are Zenith, the commander of GalaxyAI. The user gives you a big goal; you run the Galaxy to get it done \
        over hours, days or weeks. Write the forecast for this mission. Nothing has run yet.

        Who you command:
        - cloud: your own computer (Claude Code with a shell, the web, git, deploys). The heavy work: research, code, \
        build, deploy, documents. Use it for everything it can do.
        - nova: acts on the user's Mac, which is signed in everywhere (mail, accounts, 2FA, files, photos). Only for \
        what needs the Mac.
        - comet: texts through iMessage. Only for messaging people and gathering replies.

        Rules: no questions before starting; decide what you can and list your assumptions. Things that only the user \
        can decide (spending money, posting publicly, texting people not on the allowlist, real choices of taste) go \
        in needsYou and are asked once, in one batch, after everything else is done. Pick the cheapest model that can \
        do each step well: haiku for tiny steps, sonnet for the bulk, opus only for hard reasoning. Fewer, larger \
        steps beat many small ones.

        Usage estimate: a share of the user's weekly Claude Max limit. A small research mission is 1–3%, building and \
        deploying a site 5–10%, a large multi-day build 15–20%.

        If the result should be kept working afterwards (a site to keep up, prices to refresh, a schedule to keep \
        current), say how in "living" with a cadence; otherwise "none".

        Today is \(stamp(now)). Allowlisted contacts Comet may text without asking: \(allowlist.isEmpty ? "none" : allowlist.joined(separator: ", ")).

        \(galaxy.isEmpty ? "" : "What the Galaxy knows about the user:\n\(galaxy)\n")
        \(context.isEmpty ? "" : "The conversation this mission came from:\n\(context)\n")
        The mission:
        \(brief)

        Reply with only this JSON:
        {"title": "short name, 2–5 words", "summary": "one or two sentences", \
        "steps": [{"title": "...", "detail": "what exactly, and what done looks like", "member": "cloud|nova|comet", "model": "haiku|sonnet|opus"}], \
        "hours": 2, "usagePercent": 4, "needsYou": ["..."], "assumptions": ["..."], "living": "none", "cadence": "daily"}
        """
    }

    // MARK: - Work (the cloud computer)

    /// Appended to Claude Code's own system prompt for every step.
    public static let worker = """
    You are the cloud computer of Zenith, the commander of GalaxyAI. You work alone and unattended on one step of a \
    mission, in this directory (the mission's workspace; files from earlier steps are here). The brief, the plan and \
    what earlier steps did are in .zenith/BRIEF.md and .zenith/LOG.md: read them first.

    - Never stop to ask. Decide, keep going, and record each assumption you made.
    - Never spend money, buy or subscribe to anything, or post publicly (social media, forums, reviews, emails to \
    others). Deploying what the brief asks for to a free host is fine. Anything that needs money or public posting \
    becomes a question in your report, and you finish everything around it.
    - Work that needs the user's Mac (signed-in apps and sites, 2FA, their files, photos) is a handoff to nova. \
    Texting someone is a handoff to comet, with the recipient.
    - When you build something visual, save screenshots as PNG files in .zenith/snapshots/ (Playwright works well) \
    and list them.
    - If the mission needs an ability no Galaxy member has, and it would be useful again, build it as a Claude Code \
    skill in skills/<name>/SKILL.md (with any scripts beside it), test it, and report it as newSkill.
    - Check your own work before you report: run it, load it, source the facts.
    - Spend tokens carefully: no re-reading what you already know, no redundant passes.

    End your final message with this JSON (omit empty fields):
    ```json
    {"summary": "what you did and where it is", "assumptions": ["..."], \
    "questions": [{"text": "...", "kind": "yesno|choice|text", "options": ["..."], "reason": "info|spend|publish|contact"}], \
    "deliverables": ["paths or URLs"], "snapshots": [".zenith/snapshots/x.png"], \
    "handoffs": [{"member": "nova|comet", "title": "...", "instructions": "...", "recipient": "for comet"}], \
    "newSkill": {"name": "...", "for": "comet|nova|zenith", "summary": "...", "path": "skills/name"}}
    ```
    """

    public static func step(_ step: Step, number: Int, of total: Int, redirect: String?) -> String {
        var text = "Step \(number) of \(total): \(step.title)\n\n\(step.detail)"
        if let redirect, !redirect.isEmpty {
            text += "\n\nThe user changed course; this comes first: \(redirect)"
        }
        return text
    }

    public static func answers(_ questions: [Question]) -> String {
        let lines = questions.map { "- \($0.text)\n  Answer: \($0.answer ?? "(no answer)")" }
        return "The user answered your questions:\n\(lines.joined(separator: "\n"))\n\nFinish the work with these answers, then report again with the same JSON."
    }

    // MARK: - Nova and Comet, through Galaxy Link

    public static func forNova(_ instructions: String, mission: String) -> String {
        """
        From Zenith, for the mission "\(mission)". Do this on the Mac, without asking first:

        \(instructions)

        Pause the instant the user touches the mouse or keyboard, and carry on once they've been idle for a minute. \
        Never spend money or post publicly. Reply with what you did and anything you couldn't do.
        """
    }

    public static func forComet(_ instructions: String, recipient: String?, mission: String) -> String {
        """
        From Zenith, for the mission "\(mission)". \(recipient.map { "Text \($0)." } ?? "Text the user.")

        \(instructions)

        If you're waiting on a reply, gather it and send it back as your result. Sign it from Zenith only if the \
        message is to the user.
        """
    }

    // MARK: - Review (Opus)

    public static let reviewer = """
    You are Zenith's reviewer. Check the finished mission in this directory against its brief in .zenith/BRIEF.md \
    and what each step reported in .zenith/LOG.md. Check for real: load the site, run the code, open the files, \
    follow the sources. Don't fix anything. End with only this JSON:
    ```json
    {"pass": true, "summary": "one or two sentences for the user", "issues": ["what's wrong, precisely"]}
    ```
    """

    public static let review = "Review the mission now."

    public static func fix(_ issues: [String]) -> String {
        "The reviewer found these problems. Fix each one, check it, and report with the same JSON:\n" +
            issues.map { "- \($0)" }.joined(separator: "\n")
    }

    // MARK: - Living

    public static func living(_ plan: LivingPlan, mission: Mission) -> String {
        """
        Upkeep for the living mission "\(mission.title)". It finished on \(mission.finishedAt.map(stamp) ?? "an earlier day"). \
        Keep it working and up to date: \(plan.task)

        Check first; change only what needs it. Never message anyone. Report with the same JSON; the summary is one line.
        """
    }

    // MARK: - Briefing file

    public static func briefFile(_ m: Mission) -> String {
        var lines = ["# \(m.title)", "", "## Brief", m.brief]
        if !m.context.isEmpty { lines += ["", "## Where it came from", m.context] }
        if let f = m.forecast {
            lines += ["", "## Plan"] + f.steps.enumerated().map { "\($0.offset + 1). [\($0.element.member.rawValue)] \($0.element.title): \($0.element.detail)" }
        }
        if !m.assumptions.isEmpty { lines += ["", "## Assumptions"] + m.assumptions.map { "- \($0)" } }
        let answered = m.questions.filter(\.isAnswered)
        if !answered.isEmpty { lines += ["", "## The user's answers"] + answered.map { "- \($0.text) → \($0.answer!)" } }
        if let redirect = m.redirect, !redirect.isEmpty { lines += ["", "## Change of course", redirect] }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func logFile(_ m: Mission) -> String {
        let done = m.steps.filter { $0.status == .done || $0.status == .failed }
        guard !done.isEmpty else { return "# Log\n\nNothing has run yet.\n" }
        return "# Log\n\n" + done.map { "## \($0.title) (\($0.member.rawValue), \($0.status.rawValue))\n\($0.summary)\n" }.joined(separator: "\n")
    }

    // MARK: - Words Zenith says without spending a token

    /// "How's my mission?" answered from the board, for Orbit, Comet and Nova.
    public static func status(_ missions: [Mission], now: Date = Date()) -> String {
        let active = missions.filter { ![.done, .failed, .stopped, .living].contains($0.status) }
        guard !active.isEmpty else {
            let living = missions.filter { $0.status == .living }.count
            return "No missions running right now." + (living > 0 ? " \(living) living \(living == 1 ? "mission is" : "missions are") being kept up to date." : "")
        }
        return active.map { m in
            let done = m.steps.filter { $0.status == .done }.count
            var line = "\(m.title): \(phrase(m.status))"
            if !m.steps.isEmpty { line += ", \(done) of \(m.steps.count) steps done" }
            if let running = m.steps.first(where: { $0.status == .running || $0.status == .waiting }) {
                line += ". Now: \(running.title) (\(running.member.name))"
            }
            let open = m.questions.filter { !$0.isAnswered }.count
            if m.status == .needsYou && open > 0 { line += ". \(open) \(open == 1 ? "question waits" : "questions wait") for you in Zenith" }
            if !m.statusNote.isEmpty && m.status != .running { line += ". \(m.statusNote)" }
            return line + "."
        }.joined(separator: "\n")
    }

    /// The one text Zenith sends unprompted: the mission is done.
    public static func doneText(_ m: Mission) -> String {
        var text = "Zenith: \(m.title) is done."
        if !m.summary.isEmpty { text += " \(m.summary)" }
        if let link = m.deliverables.first(where: { $0.hasPrefix("http") }) { text += " \(link)" }
        text += " Everything is on the mission board."
        return text
    }

    public static func phrase(_ status: MissionStatus) -> String {
        switch status {
        case .forecasting: return "writing the forecast"
        case .awaitingLaunch: return "forecast ready, waiting for your thumbs up"
        case .queued: return "queued"
        case .running: return "working"
        case .paused: return "paused"
        case .needsYou: return "needs you"
        case .reviewing: return "checking the work"
        case .done: return "done"
        case .living: return "living"
        case .failed: return "stopped on a problem"
        case .stopped: return "stopped"
        }
    }

    static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE d MMMM yyyy, HH:mm"
        return f.string(from: date)
    }
}
