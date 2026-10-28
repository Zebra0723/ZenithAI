import SwiftUI
import ZenithCore

/// Forecast → Working → Needs you → Done → Living, under the sky.
struct BoardView: View {
    @ObservedObject var navigation: Navigation
    @ObservedObject private var store = Store.shared
    @ObservedObject private var commander = Commander.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            PageTitle(eyebrow: eyebrow, title: headline, subtitle: subtitle) { Clock() }
                .padding(.horizontal, 48)
                .padding(.top, 54)

            if store.missions.isEmpty {
                Panel(padding: 0) {
                    VStack(spacing: 0) {
                        EmptyState(title: "Nothing in the sky yet",
                                   detail: "Give Zenith a big goal: a site to build and launch, a decision to research, a trip to organize. It forecasts the plan first and starts on your thumbs up.")
                        Button { navigation.section = .new } label: { Label("New mission", systemImage: "plus") }
                            .buttonStyle(ZenithButtonStyle(kind: .primary))
                            .padding(.bottom, 50)
                    }
                }
                .padding(.horizontal, 48)
                Spacer()
            } else {
                if let live = inFlight.first {
                    InFlightCard(mission: live, others: inFlight.count - 1) { navigation.open(live.id) }
                        .padding(.horizontal, 48)
                }
                GeometryReader { geo in
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(BoardColumn.allCases) { column in
                                Lane(column: column, missions: missions(in: column), navigation: navigation)
                                    .frame(width: max(214, (geo.size.width - 96 - 14 * 4) / 5))
                            }
                        }
                        .padding(.horizontal, 48)
                        .padding(.bottom, 28)
                        .frame(minHeight: geo.size.height, alignment: .top)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
    }

    private var inFlight: [Mission] { store.missions.filter { $0.isActive }.sorted { ($0.launchedAt ?? $0.createdAt) < ($1.launchedAt ?? $1.createdAt) } }

    private func missions(in column: BoardColumn) -> [Mission] {
        let list = store.missions.filter { $0.column == column }
        switch column {
        case .done, .living: return list.sorted { ($0.finishedAt ?? $0.updatedAt) > ($1.finishedAt ?? $1.updatedAt) }
        default: return list.sorted { $0.createdAt < $1.createdAt }
        }
    }

    private var eyebrow: String {
        "\(Date().formatted(.dateTime.weekday(.wide))) \(SkyPalette.partOfDay(Date()))"
    }

    private var headline: String {
        let working = store.missions.filter { $0.column == .working }.count
        let waiting = store.missions.filter { $0.column == .needsYou }.count
        if working == 0 && waiting == 0 { return "All quiet." }
        var parts: [String] = []
        if working > 0 { parts.append("\(working) in flight") }
        if waiting > 0 { parts.append("\(waiting) \(waiting == 1 ? "needs" : "need") you") }
        return parts.joined(separator: ", ") + "."
    }

    private var subtitle: String {
        guard let r = commander.reading else { return "Every mission, from forecast to done." }
        return String(format: "The Galaxy has used %@ of this week, under a %.0f%% cap. ", Format.percent(r.usedPercent), r.capPercent) +
            "Nothing reaches your phone until a mission is done."
    }
}

/// The mission working right now, large: what it's doing this second.
private struct InFlightCard: View {
    let mission: Mission
    let others: Int
    let open: () -> Void
    @ObservedObject private var commander = Commander.shared
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(alignment: .center, spacing: 26) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        PulseDot()
                        Eyebrow("In flight" + (others > 0 ? " · and \(others) more" : ""), color: Theme.sunSoft)
                    }
                    Text(mission.title).font(Theme.display(28)).tracking(-0.5).foregroundStyle(Theme.ink)
                    if let live = commander.live[mission.id] {
                        HStack(spacing: 10) {
                            MemberTag(member: live.member)
                            Text(live.text).font(Theme.mono(12)).foregroundStyle(Theme.ink2).lineLimit(1)
                        }
                    } else {
                        Text(Prompts.phrase(mission.status).sentenceCased).font(Theme.body(13)).foregroundStyle(Theme.ink2)
                    }
                }
                Spacer(minLength: 20)
                VStack(alignment: .trailing, spacing: 10) {
                    if let at = mission.launchedAt {
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            Text(Format.elapsed(ctx.date.timeIntervalSince(at))).font(Theme.numeral(34, weight: .ultraLight))
                        }
                    }
                    HStack(spacing: 10) {
                        Text("\(mission.steps.filter { $0.status == .done }.count) of \(mission.steps.count) steps")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.ink3)
                        Meter(value: mission.progress, height: 3).frame(width: 140)
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 22)
            .glass(radius: 22, tint: Theme.sun)
            .scaleEffect(hovering ? 1.004 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

private struct Lane: View {
    let column: BoardColumn
    let missions: [Mission]
    @ObservedObject var navigation: Navigation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Circle().fill(Theme.color(column)).frame(width: 7, height: 7)
                    .shadow(color: Theme.color(column).opacity(0.8), radius: 4)
                    .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 1 }
                Text(column.title).font(Theme.display(18, weight: .regular))
                Spacer()
                Text("\(missions.count)").font(Theme.numeral(15, weight: .light)).foregroundStyle(Theme.ink3)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 4)

            if missions.isEmpty {
                Text(emptyLine)
                    .font(Theme.body(11.5)).foregroundStyle(Theme.ink3)
                    .multilineTextAlignment(.center)
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 84)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [3, 5])))
            }
            ForEach(missions) { m in
                MissionCard(mission: m) { navigation.open(m.id) }
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var emptyLine: String {
        switch column {
        case .forecast: return "Forecasts wait here for a thumbs up"
        case .working: return "Nothing running"
        case .needsYou: return "Nothing waiting on you"
        case .done: return "Finished missions land here"
        case .living: return "Results kept up to date"
        }
    }
}

struct MissionCard: View {
    let mission: Mission
    let open: () -> Void
    @ObservedObject private var commander = Commander.shared
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .top) {
                    Text(mission.title)
                        .font(Theme.display(16.5, weight: .regular))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    if mission.isActive { PulseDot().padding(.top, 5) }
                }
                if let live = commander.live[mission.id] {
                    Text(live.text)
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.sunSoft)
                        .lineLimit(2)
                } else if !line.isEmpty {
                    Text(line).font(Theme.body(12)).lineSpacing(2).foregroundStyle(Theme.ink2).lineLimit(3)
                }
                if !mission.steps.isEmpty && mission.column == .working {
                    Meter(value: mission.progress, color: mission.isActive ? Theme.sun : Theme.ink3, height: 2)
                }
                HStack(spacing: 6) {
                    if let member = mission.activeMember {
                        MemberTag(member: member)
                    } else if let f = mission.forecast, mission.column == .forecast {
                        Text("\(Format.hours(f.hours)) · \(Format.percent(f.usagePercent))")
                            .font(Theme.numeral(12, weight: .regular)).foregroundStyle(Theme.ink2)
                    } else if mission.status == .failed {
                        Pill(text: "Stopped on a problem", color: Theme.alert)
                    }
                    Spacer()
                    Text(timeLabel).font(Theme.numeral(11, weight: .regular)).foregroundStyle(Theme.ink3)
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(radius: 16, tint: mission.isActive ? Theme.sun : nil, strong: hovering)
            .offset(y: hovering ? -1 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }

    private var line: String {
        switch mission.status {
        case .forecasting: return "Writing the forecast…"
        case .awaitingLaunch: return mission.forecast?.summary ?? ""
        case .needsYou:
            let n = mission.openQuestions.count
            return "\(n) \(n == 1 ? "question" : "questions") in one batch"
        case .done, .living: return mission.summary
        default: return mission.statusNote.isEmpty ? Prompts.phrase(mission.status).sentenceCased : mission.statusNote
        }
    }

    private var timeLabel: String {
        if mission.isActive, let at = mission.launchedAt { return Format.elapsed(Date().timeIntervalSince(at)) }
        if let living = mission.living, mission.status == .living { return "next " + Format.time(living.nextRun) }
        return Format.date(mission.finishedAt ?? mission.updatedAt)
    }
}
