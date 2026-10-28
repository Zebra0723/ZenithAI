import SwiftUI
import ZenithCore

/// A scrubbable time-lapse of a mission: cloud screen snapshots, Nova's actions and Comet's
/// messages, on one timeline.
struct ReplayView: View {
    @ObservedObject var navigation: Navigation
    @ObservedObject private var store = Store.shared

    private var missions: [Mission] {
        store.missions.filter { $0.launchedAt != nil && $0.timeline.count > 1 }
            .sorted { ($0.finishedAt ?? $0.updatedAt) > ($1.finishedAt ?? $1.updatedAt) }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow("Replay").padding(.horizontal, 10).padding(.bottom, 10)
                if missions.isEmpty {
                    Text("Missions appear here once they've run.").font(Theme.body(12)).foregroundStyle(Theme.ink3).padding(.horizontal, 10)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(missions) { m in
                            Button { navigation.replayID = m.id } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(m.title).font(.system(size: 12.5, weight: selected?.id == m.id ? .semibold : .regular))
                                        .foregroundStyle(Theme.ink).lineLimit(2).multilineTextAlignment(.leading)
                                    Text(Format.date(m.finishedAt ?? m.updatedAt)).font(Theme.mono(10)).foregroundStyle(Theme.ink3)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(selected?.id == m.id ? Theme.surface : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .padding(.top, 52)
            .padding(.horizontal, 12)
            .frame(width: 236)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.raised)
            .overlay(alignment: .trailing) { Rectangle().fill(Theme.line).frame(width: 1) }

            if let m = selected {
                ReplayStage(mission: m).id(m.id)
            } else {
                VStack { EmptyState(title: "Nothing to replay yet", detail: "Every mission is recorded as it runs. Pick one on the left to scrub through it.") }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var selected: Mission? {
        if let id = navigation.replayID, let m = store.mission(id) { return m }
        return missions.first
    }
}

private struct ReplayStage: View {
    let mission: Mission
    @ObservedObject private var store = Store.shared
    @State private var cursor: Double = 0
    @State private var playing = false
    private let lanes: [Member] = [.zenith, .cloud, .nova, .comet, .nebula]
    private let clock = Timer.publish(every: 0.12, on: .main, in: .common).autoconnect()

    private var events: [TimelineEvent] { mission.timeline }
    private var index: Int { min(max(0, Int(cursor.rounded())), max(0, events.count - 1)) }
    private var current: TimelineEvent? { events.isEmpty ? nil : events[index] }
    private var start: Date { events.first?.at ?? Date() }
    private var span: TimeInterval { max(1, (events.last?.at ?? Date()).timeIntervalSince(start)) }

    /// The last snapshot at or before the cursor.
    private var snapshot: TimelineEvent? {
        events.prefix(index + 1).last { $0.kind == .snapshot && $0.file != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("Mission replay")
                    Text(mission.title).font(Theme.display(24))
                }
                Spacer()
                if let c = current {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("+" + Format.elapsed(c.at.timeIntervalSince(start))).font(Theme.numeral(18, weight: .semibold))
                        Text(Format.date(c.at)).font(Theme.mono(10.5)).foregroundStyle(Theme.ink3)
                    }
                }
            }

            stage

            lanesView

            HStack(spacing: 14) {
                Button {
                    if index >= events.count - 1 { cursor = 0 }
                    playing.toggle()
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Theme.ink, in: Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: [])
                Slider(value: $cursor, in: 0...Double(max(1, events.count - 1)))
                    .tint(Theme.sun)
                Text("\(index + 1) / \(events.count)").font(Theme.mono(10.5)).foregroundStyle(Theme.ink3).frame(width: 74, alignment: .trailing)
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 50)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onReceive(clock) { _ in
            guard playing else { return }
            if index >= events.count - 1 { playing = false } else { cursor = Double(index + 1) }
        }
    }

    private var stage: some View {
        HStack(alignment: .top, spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.night)
                if let snap = snapshot, let file = snap.file {
                    SnapshotImage(url: store.snapshots(mission.id).appendingPathComponent(file))
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(14)
                } else {
                    VStack(spacing: 10) {
                        ZenithGlyph(live: true, onNight: true).frame(width: 30, height: 30)
                        Text("No cloud screen yet at this point").font(Theme.body(12)).foregroundStyle(Theme.nightInk2)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 260, maxHeight: 420)

            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("Around this moment").padding(.bottom, 10)
                let lo = max(0, index - 5)
                let hi = max(lo, min(events.count, index + 7))
                ForEach(Array(events[lo..<hi].enumerated()), id: \.element.id) { offset, e in
                    let isNow = lo + offset == index
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Rectangle().fill(isNow ? Theme.sun : .clear).frame(width: 2, height: 14)
                        Text(e.member == .cloud ? "Cloud" : e.member.name).font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(isNow ? Theme.ink : Theme.ink3).frame(width: 50, alignment: .leading)
                        Text(e.text).font(e.kind == .tool ? Theme.mono(10.5) : Theme.body(11.5))
                            .foregroundStyle(isNow ? Theme.ink : Theme.ink2).lineLimit(isNow ? 4 : 1)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture { cursor = Double(lo + offset) }
                }
            }
            .frame(width: 330, alignment: .topLeading)
        }
    }

    private var lanesView: some View {
        VStack(spacing: 0) {
            ForEach(lanes, id: \.self) { lane in
                HStack(spacing: 12) {
                    Text(lane == .cloud ? "Cloud" : lane.name).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.ink2)
                        .frame(width: 58, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Theme.line).frame(height: 1)
                            ForEach(laneEvents(lane)) { e in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(tickColor(e))
                                    .frame(width: e.kind == .tool ? 1.5 : 3, height: e.kind == .tool ? 8 : 14)
                                    .offset(x: x(e.at, geo.size.width))
                            }
                            if let c = current {
                                Rectangle().fill(Theme.sun).frame(width: 2, height: 28).offset(x: x(c.at, geo.size.width) - 1)
                            }
                        }
                        .frame(height: geo.size.height)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { v in seek(to: v.location.x / max(1, geo.size.width)) })
                    }
                    .frame(height: 28)
                }
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    private func laneEvents(_ lane: Member) -> [TimelineEvent] {
        events.filter { $0.member == lane || (lane == .cloud && $0.member == .orbit) }
    }

    private func x(_ at: Date, _ width: CGFloat) -> CGFloat {
        CGFloat(at.timeIntervalSince(start) / span) * max(0, width - 3)
    }

    private func tickColor(_ e: TimelineEvent) -> Color {
        switch e.kind {
        case .snapshot: return Theme.calm
        case .error: return Theme.alert
        case .question, .answer: return Theme.sunDeep
        case .done: return Theme.good
        case .tool: return Theme.ink3
        default: return Theme.ink
        }
    }

    /// Moves the cursor to the event nearest a point in time.
    private func seek(to fraction: CGFloat) {
        guard !events.isEmpty else { return }
        let target = start.addingTimeInterval(span * Double(min(max(fraction, 0), 1)))
        let i = events.firstIndex { $0.at >= target } ?? events.count - 1
        cursor = Double(i)
        playing = false
    }
}
