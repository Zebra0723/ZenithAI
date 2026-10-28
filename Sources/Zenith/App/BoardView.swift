import SwiftUI
import ZenithCore

/// Forecast → Working → Needs you → Done → Living.
struct BoardView: View {
    @ObservedObject var navigation: Navigation
    @ObservedObject private var store = Store.shared
    @ObservedObject private var commander = Commander.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            PageTitle(eyebrow: "Mission board", title: headline, subtitle: subtitle) {
                Button { navigation.section = .new } label: {
                    Label("New mission", systemImage: "plus").labelStyle(.titleAndIcon)
                }
                .buttonStyle(ZenithButtonStyle(kind: .primary))
            }
            .padding(.horizontal, 44)
            .padding(.top, 50)

            if store.missions.isEmpty {
                Panel {
                    EmptyState(title: "No missions yet",
                               detail: "Give Zenith a big goal: a site to build and launch, a decision to research, a trip to organize. It forecasts the plan first and starts on your thumbs up.")
                }
                .padding(.horizontal, 44)
                Spacer()
            } else {
                GeometryReader { geo in
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(BoardColumn.allCases) { column in
                                BoardColumnView(column: column, missions: missions(in: column), navigation: navigation)
                                    .frame(width: max(208, (geo.size.width - 88 - 14 * 4) / 5))
                            }
                        }
                        .padding(.horizontal, 44)
                        .padding(.bottom, 30)
                        .frame(minHeight: geo.size.height, alignment: .top)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
    }

    private func missions(in column: BoardColumn) -> [Mission] {
        let list = store.missions.filter { $0.column == column }
        switch column {
        case .done, .living: return list.sorted { ($0.finishedAt ?? $0.updatedAt) > ($1.finishedAt ?? $1.updatedAt) }
        default: return list.sorted { $0.createdAt < $1.createdAt }
        }
    }

    private var headline: String {
        let working = store.missions.filter { $0.column == .working }.count
        let waiting = store.missions.filter { $0.column == .needsYou }.count
        if working == 0 && waiting == 0 { return "All quiet" }
        var parts: [String] = []
        if working > 0 { parts.append("\(working) working") }
        if waiting > 0 { parts.append("\(waiting) \(waiting == 1 ? "needs" : "need") you") }
        return parts.joined(separator: ", ")
    }

    private var subtitle: String {
        guard let r = commander.reading else { return "Every mission, from forecast to done." }
        return String(format: "The Galaxy has used %@ of the week, under a %.0f%% cap. ", Format.percent(r.usedPercent), r.capPercent) +
            (store.missions.contains { $0.isActive } ? "Nothing is sent to you until a mission is done." : "Heavy work waits for the overnight window.")
    }
}

private struct BoardColumnView: View {
    let column: BoardColumn
    let missions: [Mission]
    @ObservedObject var navigation: Navigation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(Theme.color(column)).frame(width: 7, height: 7)
                Text(column.title).font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Text("\(missions.count)").font(Theme.mono(11)).foregroundStyle(Theme.ink3)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 2)

            if missions.isEmpty {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(height: 74)
                    .overlay(Text(emptyLine).font(Theme.body(11.5)).foregroundStyle(Theme.ink3)
                        .multilineTextAlignment(.center).padding(10))
            }
            ForEach(missions) { m in
                MissionCard(mission: m) { navigation.open(m.id) }
            }
        }
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
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text(mission.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    if mission.isActive {
                        PulseDot()
                    }
                }
                if let live = commander.live[mission.id] {
                    Text(live.text)
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.sunDeep)
                        .lineLimit(2)
                } else if !line.isEmpty {
                    Text(line).font(Theme.body(11.5)).foregroundStyle(Theme.ink2).lineLimit(3)
                }
                if !mission.steps.isEmpty && mission.column == .working {
                    Meter(value: mission.progress, color: mission.isActive ? Theme.sun : Theme.ink3, height: 3)
                }
                HStack(spacing: 6) {
                    if let member = mission.activeMember {
                        Pill(text: member.name, color: Theme.sunDeep)
                    } else if let f = mission.forecast, mission.column == .forecast {
                        Text("\(Format.hours(f.hours)) · \(Format.percent(f.usagePercent))")
                            .font(Theme.mono(10.5)).foregroundStyle(Theme.ink2)
                    }
                    Spacer()
                    Text(timeLabel).font(Theme.mono(10)).foregroundStyle(Theme.ink3)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(mission.isActive ? Theme.sun.opacity(0.7) : (hovering ? Theme.lineStrong : Theme.line), lineWidth: 1))
            .shadow(color: .black.opacity(hovering ? 0.06 : 0.025), radius: hovering ? 10 : 4, y: 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
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

/// The sun, breathing: something is working right now.
struct PulseDot: View {
    @State private var on = false

    var body: some View {
        Circle()
            .fill(Theme.sun)
            .frame(width: 7, height: 7)
            .background(Circle().fill(Theme.sun.opacity(0.25)).scaleEffect(on ? 2.4 : 1))
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { on = true }
            }
    }
}
