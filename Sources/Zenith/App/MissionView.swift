import AppKit
import SwiftUI
import ZenithCore

/// One mission: the live timeline, the active member, cloud snapshots, usage so far, and
/// pause, redirect and stop.
struct MissionView: View {
    let id: String
    @ObservedObject var navigation: Navigation
    @ObservedObject private var store = Store.shared
    @ObservedObject private var commander = Commander.shared
    @State private var redirecting = false
    @State private var redirectText = ""
    @State private var confirmStop = false

    var body: some View {
        if let m = store.mission(id) {
            Page(maxWidth: 1180) {
                header(m)
                switch m.status {
                case .forecasting, .awaitingLaunch:
                    ForecastPanel(mission: m) { commander.launch(id) } discard: {
                        commander.delete(id)
                        navigation.missionID = nil
                    }
                default:
                    HStack(alignment: .top, spacing: 22) {
                        VStack(alignment: .leading, spacing: 22) {
                            if let note = notice(m) { noticePanel(note, m) }
                            NowPanel(mission: m, live: commander.live[id])
                            TimelinePanel(mission: m)
                        }
                        .frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 22) {
                            GalaxyStrip(active: m.activeMember, used: Set(m.steps.map(\.member)))
                            StepsPanel(mission: m)
                            UsagePanel(mission: m, reading: commander.reading)
                            if !snapshots(m).isEmpty { SnapshotsPanel(mission: m, events: snapshots(m)) }
                            if !m.deliverables.isEmpty { DeliverablesPanel(mission: m) }
                            if let review = m.review { ReviewPanel(review: review) }
                            if !m.assumptions.isEmpty { ListPanel(title: "Assumptions", items: m.assumptions) }
                        }
                        .frame(width: 330)
                    }
                }
            }
        }
    }

    private func snapshots(_ m: Mission) -> [TimelineEvent] { m.timeline.filter { $0.kind == .snapshot && $0.file != nil } }

    private func header(_ m: Mission) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { navigation.missionID = nil } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                    Text("Mission board").font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Theme.ink2)
            }
            .buttonStyle(.plain)

            HStack(alignment: .bottom, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        StatusPill(mission: m)
                        Text("From \(m.source.title)").font(.system(size: 11)).foregroundStyle(Theme.ink3)
                        if m.onCloud { Pill(text: "Cloud", color: Theme.calm) }
                    }
                    Text(m.title).font(Theme.display(26)).tracking(-0.3)
                    Text(m.brief).font(Theme.body(13)).foregroundStyle(Theme.ink2).lineLimit(3)
                        .frame(maxWidth: 680, alignment: .leading)
                }
                Spacer(minLength: 10)
                controls(m)
            }
        }
    }

    @ViewBuilder
    private func controls(_ m: Mission) -> some View {
        HStack(spacing: 8) {
            switch m.status {
            case .running, .reviewing, .queued:
                Button { commander.pause(id) } label: { Label("Pause", systemImage: "pause") }
                    .buttonStyle(ZenithButtonStyle())
                redirectButton
                Button { confirmStop = true } label: { Label("Stop", systemImage: "stop") }
                    .buttonStyle(ZenithButtonStyle(kind: .alert))
            case .paused:
                Button { commander.resume(id) } label: { Label("Resume", systemImage: "play") }
                    .buttonStyle(ZenithButtonStyle(kind: .primary))
                redirectButton
                Button { confirmStop = true } label: { Label("Stop", systemImage: "stop") }
                    .buttonStyle(ZenithButtonStyle(kind: .alert))
            case .needsYou:
                Button { navigation.section = .needsYou } label: { Label("Answer", systemImage: "arrow.right") }
                    .buttonStyle(ZenithButtonStyle(kind: .primary))
                Button { confirmStop = true } label: { Label("Stop", systemImage: "stop") }
                    .buttonStyle(ZenithButtonStyle(kind: .alert))
            case .done, .living, .failed, .stopped:
                Button {
                    navigation.replayID = id
                    navigation.section = .replay
                } label: { Label("Replay", systemImage: "clock.arrow.circlepath") }
                    .buttonStyle(ZenithButtonStyle())
                Button {
                    commander.delete(id)
                    navigation.missionID = nil
                } label: { Label("Delete", systemImage: "trash") }
                    .buttonStyle(ZenithButtonStyle(kind: .alert))
            default:
                EmptyView()
            }
        }
        .confirmationDialog("Stop this mission?", isPresented: $confirmStop) {
            Button("Stop the mission", role: .destructive) { commander.stop(id) }
        } message: {
            Text("Work in flight is stopped. What's done so far stays on the board.")
        }
    }

    private var redirectButton: some View {
        Button { redirecting = true } label: { Label("Redirect", systemImage: "arrow.triangle.turn.up.right.diamond") }
            .buttonStyle(ZenithButtonStyle())
            .popover(isPresented: $redirecting, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Change course").font(Theme.display(14))
                    Text("The step in flight restarts with this first. The rest of the plan stays.")
                        .font(Theme.body(12)).foregroundStyle(Theme.ink2)
                    TextField("Use the green logo, and skip the blog", text: $redirectText, axis: .vertical)
                        .lineLimit(3...6)
                        .zenithField()
                    HStack {
                        Spacer()
                        Button("Cancel") { redirecting = false }.buttonStyle(ZenithButtonStyle())
                        Button("Redirect") {
                            commander.redirect(id, redirectText)
                            redirectText = ""
                            redirecting = false
                        }
                        .buttonStyle(ZenithButtonStyle(kind: .primary))
                        .disabled(redirectText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(18)
                .frame(width: 380)
            }
    }

    private func notice(_ m: Mission) -> String? {
        switch m.status {
        case .queued, .paused, .failed: return m.statusNote.isEmpty ? nil : m.statusNote
        case .needsYou: return "Everything that doesn't need you is done. \(m.openQuestions.count) \(m.openQuestions.count == 1 ? "question waits" : "questions wait") in one batch."
        default: return nil
        }
    }

    private func noticePanel(_ text: String, _ m: Mission) -> some View {
        HStack(spacing: 12) {
            Rectangle().fill(m.status == .failed || m.status == .needsYou ? Theme.alert : Theme.ink3).frame(width: 3)
            Text(text).font(Theme.body(13)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if m.status == .failed {
                Button("Try again") { commander.resume(id) }.buttonStyle(ZenithButtonStyle())
            }
        }
        .padding(.vertical, 12)
        .padding(.trailing, 14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Now

private struct NowPanel: View {
    let mission: Mission
    let live: Commander.LiveLine?

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle().fill(live != nil ? Theme.sunWash : Theme.raised)
                ZenithGlyph(live: live != nil).frame(width: 22, height: 22)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 5) {
                Eyebrow(live.map { "Now · \($0.member.name)" } ?? "Now", color: live != nil ? Theme.sunDeep : Theme.ink3)
                Text(live?.text ?? idleLine)
                    .font(live != nil ? Theme.mono(12.5) : Theme.body(13.5))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
            }
            Spacer()
            if let at = mission.launchedAt, !mission.isFinished {
                VStack(alignment: .trailing, spacing: 5) {
                    Eyebrow("Running for")
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(Format.elapsed(ctx.date.timeIntervalSince(at))).font(Theme.numeral(15, weight: .semibold))
                    }
                }
            } else if let at = mission.finishedAt, let start = mission.launchedAt {
                VStack(alignment: .trailing, spacing: 5) {
                    Eyebrow("Took")
                    Text(Format.elapsed(at.timeIntervalSince(start))).font(Theme.numeral(15, weight: .semibold))
                }
            }
        }
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(live != nil ? Theme.sun.opacity(0.6) : Theme.line, lineWidth: 1))
    }

    private var idleLine: String {
        switch mission.status {
        case .done: return mission.summary.isEmpty ? "Done." : mission.summary
        case .living: return "Living: \(mission.living?.task ?? "kept up to date")"
        case .needsYou: return "Waiting on your answers."
        default: return mission.statusNote.isEmpty ? Prompts.phrase(mission.status).sentenceCased : mission.statusNote
        }
    }
}

// MARK: - Timeline

struct TimelinePanel: View {
    let mission: Mission
    @State private var showTools = true

    private var events: [TimelineEvent] {
        let all = showTools ? mission.timeline : mission.timeline.filter { $0.kind != .tool }
        return Array(all.suffix(400).reversed())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Eyebrow("Timeline")
                Spacer()
                Button(showTools ? "Hide tool calls" : "Show tool calls") { showTools.toggle() }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.ink2)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            Rule()
            if events.isEmpty {
                Text("Nothing yet.").font(Theme.body(12.5)).foregroundStyle(Theme.ink3).padding(18)
            }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(events) { e in
                    TimelineRow(event: e)
                }
            }
            .padding(.vertical, 6)
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}

struct TimelineRow: View {
    let event: TimelineEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(Format.time(event.at)).font(Theme.mono(10.5)).foregroundStyle(Theme.ink3).frame(width: 62, alignment: .leading)
            Text(event.member.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
                .frame(width: 92, alignment: .leading)
            Text(event.text)
                .font(event.kind == .tool ? Theme.mono(11.5) : Theme.body(12.5))
                .foregroundStyle(event.kind == .tool ? Theme.ink2 : Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, event.kind == .tool ? 4 : 8)
        .background(event.kind == .done || event.kind == .question ? Theme.sunWash.opacity(0.6) : .clear)
    }

    private var color: Color {
        switch event.kind {
        case .error: return Theme.alert
        case .done: return Theme.good
        case .question, .answer: return Theme.sunDeep
        default: return Theme.ink2
        }
    }
}

// MARK: - Side panels

/// Which Galaxy members a mission uses, and who's working right now.
struct GalaxyStrip: View {
    let active: Member?
    let used: Set<Member>
    @ObservedObject private var connector = Connector.shared

    private let members: [Member] = [.zenith, .cloud, .nova, .comet, .nebula]

    var body: some View {
        Panel(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow("Galaxy")
                HStack(spacing: 0) {
                    ForEach(Array(members.enumerated()), id: \.element) { i, member in
                        if i > 0 {
                            Rectangle().fill(Theme.line).frame(height: 1).frame(maxWidth: .infinity)
                        }
                        VStack(spacing: 7) {
                            ZStack {
                                Circle().fill(member == active ? Theme.sun : (lit(member) ? Theme.ink : Theme.raised))
                                Circle().strokeBorder(member == active ? Theme.sun : Theme.lineStrong, lineWidth: 1)
                                if member == active {
                                    Circle().strokeBorder(Theme.sun.opacity(0.35), lineWidth: 4).padding(-5)
                                }
                            }
                            .frame(width: 14, height: 14)
                            Text(member == .cloud ? "Cloud" : member.name)
                                .font(.system(size: 10.5, weight: member == active ? .semibold : .regular))
                                .foregroundStyle(member == active ? Theme.ink : (lit(member) ? Theme.ink2 : Theme.ink3))
                        }
                        .fixedSize()
                        .help(member.role)
                    }
                }
            }
        }
    }

    private func lit(_ m: Member) -> Bool { m == .zenith || used.contains(m) }
}

private struct StepsPanel: View {
    let mission: Mission

    var body: some View {
        Panel(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Eyebrow("Plan")
                    Spacer()
                    Text("\(mission.steps.filter { $0.status == .done }.count) of \(mission.steps.count)")
                        .font(Theme.mono(10.5)).foregroundStyle(Theme.ink3)
                }
                ForEach(mission.steps) { step in
                    HStack(alignment: .top, spacing: 10) {
                        icon(step.status).frame(width: 14, height: 14).padding(.top, 1)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.title).font(.system(size: 12.5, weight: step.status == .running ? .semibold : .regular))
                                .foregroundStyle(step.status == .skipped ? Theme.ink3 : Theme.ink)
                                .strikethrough(step.status == .skipped, color: Theme.ink3)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(step.member.name) · \(step.model.name)").font(Theme.mono(10)).foregroundStyle(Theme.ink3)
                        }
                    }
                    .help(step.summary.isEmpty ? step.detail : step.summary)
                }
            }
        }
    }

    @ViewBuilder
    private func icon(_ status: StepStatus) -> some View {
        switch status {
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good).font(.system(size: 12))
        case .running, .waiting: PulseDot()
        case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.alert).font(.system(size: 12))
        case .skipped: Image(systemName: "minus.circle").foregroundStyle(Theme.ink3).font(.system(size: 12))
        case .pending: Circle().strokeBorder(Theme.lineStrong, lineWidth: 1.2).frame(width: 11, height: 11)
        }
    }
}

private struct UsagePanel: View {
    let mission: Mission
    let reading: BudgetReading?
    @ObservedObject private var store = Store.shared

    var body: some View {
        let percent = mission.usage.units / max(store.settings.budget.unitsPerPercent, 0.0001)
        Panel(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow("Usage so far")
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Format.percent(percent)).font(Theme.numeral(24, weight: .semibold))
                    Text("of the week").font(Theme.body(12)).foregroundStyle(Theme.ink2)
                    Spacer()
                    if let f = mission.forecast {
                        Text("forecast \(Format.percent(f.usagePercent))").font(Theme.mono(10.5)).foregroundStyle(Theme.ink3)
                    }
                }
                if let f = mission.forecast, f.usagePercent > 0 {
                    Meter(value: percent / f.usagePercent, color: percent > f.usagePercent ? Theme.alert : Theme.sun)
                }
                VStack(spacing: 6) {
                    ForEach(ModelTier.allCases.reversed(), id: \.self) { tier in
                        let c = mission.usage.counts(tier)
                        if c.total > 0 {
                            HStack {
                                Text(tier.name).font(.system(size: 11.5))
                                Spacer()
                                Text(Format.tokens(c.total) + " tokens").font(Theme.mono(10.5)).foregroundStyle(Theme.ink2)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct SnapshotsPanel: View {
    let mission: Mission
    let events: [TimelineEvent]
    @ObservedObject private var store = Store.shared

    var body: some View {
        Panel(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow("Cloud screen")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(events.suffix(6)) { e in
                        SnapshotImage(url: store.snapshots(mission.id).appendingPathComponent(e.file ?? ""))
                            .frame(height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                            .onTapGesture { NSWorkspace.shared.open(store.snapshots(mission.id).appendingPathComponent(e.file ?? "")) }
                            .help(e.text)
                    }
                }
            }
        }
    }
}

struct SnapshotImage: View {
    let url: URL

    var body: some View {
        if let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
        } else {
            Rectangle().fill(Theme.raised)
                .overlay(Image(systemName: "photo").foregroundStyle(Theme.ink3))
        }
    }
}

private struct DeliverablesPanel: View {
    let mission: Mission
    @ObservedObject private var store = Store.shared

    var body: some View {
        Panel(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow("Results")
                    Spacer()
                    if !mission.onCloud {
                        Button("Open workspace") { NSWorkspace.shared.open(store.workspace(mission.id)) }
                            .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.ink2)
                    }
                }
                ForEach(mission.deliverables, id: \.self) { d in
                    Button { open(d) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: d.hasPrefix("http") ? "link" : "doc").font(.system(size: 10.5)).foregroundStyle(Theme.ink3)
                            Text(d).font(Theme.mono(11)).foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func open(_ d: String) {
        if d.hasPrefix("http"), let url = URL(string: d) {
            NSWorkspace.shared.open(url)
        } else if !mission.onCloud {
            let url = d.hasPrefix("/") ? URL(fileURLWithPath: d) : store.workspace(mission.id).appendingPathComponent(d)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

private struct ReviewPanel: View {
    let review: Review

    var body: some View {
        Panel(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow("Self-check")
                    Spacer()
                    Pill(text: review.pass ? "Passed" : "\(review.issues.count) issues", color: review.pass ? Theme.good : Theme.alert)
                }
                if !review.summary.isEmpty {
                    Text(review.summary).font(Theme.body(12.5)).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
                }
                if !review.pass {
                    ForEach(review.issues, id: \.self) { issue in
                        Text(issue).font(Theme.body(12)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

struct ListPanel: View {
    let title: String
    let items: [String]

    var body: some View {
        Panel(padding: 16) {
            VStack(alignment: .leading, spacing: 9) {
                Eyebrow(title)
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Rectangle().fill(Theme.ink3).frame(width: 7, height: 1)
                        Text(item).font(Theme.body(12)).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
