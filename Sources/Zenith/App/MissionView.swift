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
            Page(maxWidth: 1220) {
                header(m)
                switch m.status {
                case .forecasting, .awaitingLaunch:
                    ForecastPanel(mission: m) { commander.launch(id) } discard: {
                        commander.delete(id)
                        navigation.missionID = nil
                    }
                default:
                    HStack(alignment: .top, spacing: 22) {
                        VStack(alignment: .leading, spacing: 20) {
                            if let note = notice(m) { noticePanel(note, m) }
                            NowPanel(mission: m, live: commander.live[id])
                            TimelinePanel(mission: m)
                        }
                        .frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 20) {
                            GalaxyMap(active: m.activeMember, used: Set(m.steps.map(\.member)))
                            StepsPanel(mission: m)
                            UsagePanel(mission: m)
                            if !snapshots(m).isEmpty { SnapshotsPanel(mission: m, events: snapshots(m)) }
                            if !m.deliverables.isEmpty { DeliverablesPanel(mission: m) }
                            if let review = m.review { ReviewPanel(review: review) }
                            if !m.assumptions.isEmpty { ListPanel(title: "Assumptions", items: m.assumptions) }
                        }
                        .frame(width: 340)
                    }
                }
            }
        }
    }

    private func snapshots(_ m: Mission) -> [TimelineEvent] { m.timeline.filter { $0.kind == .snapshot && $0.file != nil } }

    private func header(_ m: Mission) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Button { navigation.missionID = nil } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                    Text("Mission board").font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Theme.ink3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(alignment: .bottom, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        StatusPill(mission: m)
                        Text("From \(m.source.title)").font(.system(size: 11.5)).foregroundStyle(Theme.ink3)
                        if m.onCloud { Pill(text: "Cloud", color: Theme.color(.cloud)) }
                    }
                    Text(m.title).font(Theme.display(42)).tracking(-0.9)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(m.brief).font(Theme.body(14)).lineSpacing(3).foregroundStyle(Theme.ink2).lineLimit(3)
                        .frame(maxWidth: 700, alignment: .leading)
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
                Button { commander.pause(id) } label: { Label("Pause", systemImage: "pause.fill") }
                    .buttonStyle(ZenithButtonStyle())
                redirectButton
                Button { confirmStop = true } label: { Label("Stop", systemImage: "stop.fill") }
                    .buttonStyle(ZenithButtonStyle(kind: .alert))
            case .paused:
                Button { commander.resume(id) } label: { Label("Resume", systemImage: "play.fill") }
                    .buttonStyle(ZenithButtonStyle(kind: .primary))
                redirectButton
                Button { confirmStop = true } label: { Label("Stop", systemImage: "stop.fill") }
                    .buttonStyle(ZenithButtonStyle(kind: .alert))
            case .needsYou:
                Button { navigation.section = .needsYou } label: { Label("Answer", systemImage: "arrow.right") }
                    .buttonStyle(ZenithButtonStyle(kind: .primary))
                Button { confirmStop = true } label: { Label("Stop", systemImage: "stop.fill") }
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
                } label: { Image(systemName: "trash") }
                    .buttonStyle(IconButtonStyle())
                    .help("Delete the mission")
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
                VStack(alignment: .leading, spacing: 14) {
                    Text("Change course").font(Theme.display(20))
                    Text("The step in flight restarts with this first. The rest of the plan stays.")
                        .font(Theme.body(12.5)).foregroundStyle(Theme.ink2)
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
                .padding(20)
                .frame(width: 400)
                .background(Color(red: 0.06, green: 0.07, blue: 0.14))
                .environment(\.colorScheme, .dark)
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
        let color = m.status == .failed || m.status == .needsYou ? Theme.alert : Theme.ink2
        return HStack(spacing: 14) {
            Image(systemName: m.status == .failed ? "exclamationmark.triangle" : (m.status == .needsYou ? "questionmark.bubble" : "clock"))
                .font(.system(size: 14)).foregroundStyle(color)
            Text(text).font(Theme.body(13.5)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if m.status == .failed {
                Button("Try again") { commander.resume(id) }.buttonStyle(ZenithButtonStyle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .glass(radius: 16, tint: m.status == .failed || m.status == .needsYou ? Theme.alert : nil)
    }
}

// MARK: - Now

private struct NowPanel: View {
    let mission: Mission
    let live: Commander.LiveLine?

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            ZStack {
                Circle().fill((live.map { Theme.color($0.member) } ?? Theme.ink3).opacity(0.14))
                if let live {
                    Circle().strokeBorder(Theme.color(live.member).opacity(0.6), lineWidth: 1)
                    PulseDot(color: Theme.color(live.member))
                } else {
                    ZenithGlyph(live: false).frame(width: 22, height: 22)
                }
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 7) {
                Eyebrow(live.map { "Now · \($0.member == .cloud ? "Cloud computer" : $0.member.name)" } ?? "Now",
                        color: live.map { Theme.color($0.member) } ?? Theme.ink3)
                Text(live?.text ?? idleLine)
                    .font(live != nil ? Theme.mono(13) : Theme.body(14.5))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
            }
            Spacer()
            if let at = mission.launchedAt, !mission.isFinished {
                VStack(alignment: .trailing, spacing: 6) {
                    Eyebrow("Running for")
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(Format.elapsed(ctx.date.timeIntervalSince(at))).font(Theme.numeral(30, weight: .ultraLight))
                    }
                }
            } else if let at = mission.finishedAt, let start = mission.launchedAt {
                VStack(alignment: .trailing, spacing: 6) {
                    Eyebrow("Took")
                    Text(Format.elapsed(at.timeIntervalSince(start))).font(Theme.numeral(30, weight: .ultraLight))
                }
            }
        }
        .padding(20)
        .glass(radius: 20, tint: live != nil ? Theme.color(live!.member) : nil)
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
                Text("Timeline").font(Theme.display(20, weight: .regular))
                Spacer()
                Button(showTools ? "Hide tool calls" : "Show tool calls") { showTools.toggle() }
                    .buttonStyle(.plain).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.ink3)
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 12)
            if events.isEmpty {
                Text("Nothing yet.").font(Theme.body(13)).foregroundStyle(Theme.ink3).padding(22)
            }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(events) { e in
                    TimelineRow(event: e)
                }
            }
            // The rail.
            .background(alignment: .leading) {
                Rectangle().fill(Theme.line).frame(width: 1).padding(.leading, 104.5)
            }
            .padding(.bottom, 14)
        }
        .glass(radius: 20)
    }
}

struct TimelineRow: View {
    let event: TimelineEvent

    private var major: Bool { event.kind != .tool }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(Format.time(event.at))
                .font(Theme.numeral(11, weight: .regular)).foregroundStyle(Theme.ink3)
                .frame(width: 84, alignment: .trailing)
                .padding(.trailing, 14)
            Circle()
                .fill(major ? Theme.color(event.member) : Theme.ink4)
                .frame(width: major ? 8 : 4, height: major ? 8 : 4)
                .shadow(color: major ? Theme.color(event.member).opacity(0.8) : .clear, radius: 4)
                .frame(width: 14)
                .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 4 }
            VStack(alignment: .leading, spacing: 3) {
                if major {
                    Text(event.member == .cloud ? "Cloud computer" : event.member.name)
                        .font(.system(size: 10.5, weight: .semibold)).tracking(0.4)
                        .foregroundStyle(event.kind == .error ? Theme.alert : Theme.color(event.member))
                }
                Text(event.text)
                    .font(major ? Theme.body(13) : Theme.mono(11))
                    .lineSpacing(2)
                    .foregroundStyle(major ? Theme.ink : Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(.leading, 14)
            Spacer(minLength: 16)
        }
        .padding(.vertical, major ? 9 : 2.5)
    }
}

// MARK: - Side panels

/// The Galaxy as a small constellation: who the mission uses, and who's working right now.
struct GalaxyMap: View {
    let active: Member?
    let used: Set<Member>

    private let members: [Member] = [.nova, .cloud, .zenith, .comet, .nebula]

    /// Points on an arc across the panel, the middle one (Zenith) at its highest.
    static func arc(count: Int, in size: CGSize) -> [CGPoint] {
        let w = Double(size.width)
        let h = Double(size.height)
        var points: [CGPoint] = []
        for i in 0..<count {
            let t = Double(i) / Double(max(1, count - 1))
            let x: Double = 18 + t * (w - 36)
            let y: Double = h * 0.78 - sin(t * Double.pi) * h * 0.5
            points.append(CGPoint(x: x, y: y))
        }
        return points
    }

    var body: some View {
        Panel(padding: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow("Galaxy")
                GeometryReader { geo in
                    let points = Self.arc(count: members.count, in: geo.size)
                    ZStack {
                        Path { p in
                            p.move(to: points[0])
                            for pt in points.dropFirst() { p.addLine(to: pt) }
                        }
                        .stroke(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                        if let active, let ai = members.firstIndex(of: active), active != .zenith {
                            Path { p in
                                p.move(to: points[2])
                                p.addLine(to: points[ai])
                            }
                            .stroke(Theme.color(active), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                            .shadow(color: Theme.color(active), radius: 4)
                        }
                        ForEach(Array(members.enumerated()), id: \.element) { i, member in
                            let on = member == active
                            let lit = member == .zenith || used.contains(member)
                            VStack(spacing: 7) {
                                ZStack {
                                    if on { Circle().fill(Theme.color(member).opacity(0.25)).frame(width: 26, height: 26) }
                                    Circle().fill(lit ? Theme.color(member) : Theme.ink4)
                                        .frame(width: on ? 12 : 8, height: on ? 12 : 8)
                                        .shadow(color: lit ? Theme.color(member) : .clear, radius: on ? 8 : 3)
                                }
                                .frame(width: 26, height: 26)
                                Text(member == .cloud ? "Cloud" : member.name)
                                    .font(.system(size: 10.5, weight: on ? .semibold : .regular))
                                    .foregroundStyle(on ? Theme.ink : (lit ? Theme.ink2 : Theme.ink3))
                                    .fixedSize()
                            }
                            .position(x: points[i].x, y: points[i].y + 10)
                            .help(member.role)
                        }
                    }
                }
                .frame(height: 104)
            }
        }
    }
}

private struct StepsPanel: View {
    let mission: Mission

    var body: some View {
        Panel(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Plan").font(Theme.display(19, weight: .regular))
                    Spacer()
                    Text("\(mission.steps.filter { $0.status == .done }.count) / \(mission.steps.count)")
                        .font(Theme.numeral(14, weight: .light)).foregroundStyle(Theme.ink3)
                }
                ForEach(mission.steps) { step in
                    HStack(alignment: .top, spacing: 12) {
                        icon(step).frame(width: 14, height: 14).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.title).font(.system(size: 12.5, weight: step.status == .running ? .semibold : .regular))
                                .foregroundStyle(step.status == .skipped ? Theme.ink3 : Theme.ink)
                                .strikethrough(step.status == .skipped, color: Theme.ink3)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 8) {
                                MemberTag(member: step.member)
                                Text(step.model.name).font(Theme.mono(10)).foregroundStyle(Theme.ink3)
                            }
                        }
                    }
                    .help(step.summary.isEmpty ? step.detail : step.summary)
                }
            }
        }
    }

    @ViewBuilder
    private func icon(_ step: Step) -> some View {
        switch step.status {
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good).font(.system(size: 12.5))
        case .running, .waiting: PulseDot(color: Theme.color(step.member))
        case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.alert).font(.system(size: 12.5))
        case .skipped: Image(systemName: "minus.circle").foregroundStyle(Theme.ink3).font(.system(size: 12.5))
        case .pending: Circle().strokeBorder(Theme.lineStrong, lineWidth: 1.2).frame(width: 11, height: 11)
        }
    }
}

private struct UsagePanel: View {
    let mission: Mission
    @ObservedObject private var store = Store.shared

    var body: some View {
        let percent = mission.usage.units / max(store.settings.budget.unitsPerPercent, 0.0001)
        let forecast = mission.forecast?.usagePercent ?? 0
        Panel(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 18) {
                    SunDial(value: forecast > 0 ? percent / forecast : 0, cap: 1, lineWidth: 5, label: "", caption: "")
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow("Usage so far")
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(Format.percent(percent)).font(Theme.numeral(28, weight: .ultraLight))
                            Text("of the week").font(.system(size: 11.5)).foregroundStyle(Theme.ink3)
                        }
                        if forecast > 0 {
                            Text("Forecast \(Format.percent(forecast))").font(.system(size: 11)).foregroundStyle(Theme.ink3)
                        }
                    }
                }
                VStack(spacing: 7) {
                    ForEach(ModelTier.allCases.reversed(), id: \.self) { tier in
                        let c = mission.usage.counts(tier)
                        if c.total > 0 {
                            HStack {
                                Text(tier.name).font(.system(size: 11.5)).foregroundStyle(Theme.ink2)
                                Spacer()
                                Text(Format.tokens(c.total) + " tokens").font(Theme.mono(10.5)).foregroundStyle(Theme.ink3)
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
        Panel(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow("Cloud screen")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(events.suffix(6)) { e in
                        SnapshotImage(url: store.snapshots(mission.id).appendingPathComponent(e.file ?? ""))
                            .frame(height: 86)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.lineStrong, lineWidth: 1))
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
            Rectangle().fill(Color.black.opacity(0.3))
                .overlay(Image(systemName: "photo").foregroundStyle(Theme.ink3))
        }
    }
}

private struct DeliverablesPanel: View {
    let mission: Mission
    @ObservedObject private var store = Store.shared

    var body: some View {
        Panel(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow("Results")
                    Spacer()
                    if !mission.onCloud {
                        Button("Open workspace") { NSWorkspace.shared.open(store.workspace(mission.id)) }
                            .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.sunSoft)
                    }
                }
                ForEach(mission.deliverables, id: \.self) { d in
                    Button { open(d) } label: {
                        HStack(spacing: 9) {
                            Image(systemName: d.hasPrefix("http") ? "link" : "doc").font(.system(size: 10.5)).foregroundStyle(Theme.ink3)
                            Text(d).font(Theme.mono(11)).foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.ink3)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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
        Panel(padding: 18, tint: review.pass ? Theme.good : Theme.alert) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow("Self-check")
                    Spacer()
                    Pill(text: review.pass ? "Passed" : "\(review.issues.count) issues", color: review.pass ? Theme.good : Theme.alert)
                }
                if !review.summary.isEmpty {
                    Text(review.summary).font(Theme.body(12.5)).lineSpacing(2).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
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
        Panel(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(title)
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Circle().fill(Theme.ink3).frame(width: 4, height: 4).alignmentGuide(.firstTextBaseline) { d in d[.bottom] + 1 }
                        Text(item).font(Theme.body(12)).lineSpacing(2).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
