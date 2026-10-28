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
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow("Replay").padding(.horizontal, 12).padding(.bottom, 8)
                if missions.isEmpty {
                    Text("Missions appear here once they've run.").font(Theme.body(12)).foregroundStyle(Theme.ink3).padding(.horizontal, 12)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(missions) { m in
                            let on = selected?.id == m.id
                            Button { navigation.replayID = m.id } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(m.title).font(Theme.display(15, weight: on ? .regular : .light))
                                        .foregroundStyle(on ? Theme.ink : Theme.ink2).lineLimit(2).multilineTextAlignment(.leading)
                                    Text(Format.date(m.finishedAt ?? m.updatedAt)).font(.system(size: 10.5)).foregroundStyle(Theme.ink3)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(on ? Theme.glassStrong : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .padding(.top, 54)
            .padding(.horizontal, 10)
            .frame(width: 250)
            .frame(maxHeight: .infinity, alignment: .top)

            if let m = selected {
                ReplayStage(mission: m).id(m.id)
            } else {
                EmptyState(title: "Nothing to replay yet", detail: "Every mission is recorded as it runs. Pick one on the left to scrub through it.")
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
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow("Mission replay")
                    Text(mission.title).font(Theme.display(34)).tracking(-0.6)
                }
                Spacer()
                if let c = current {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("+" + Format.elapsed(c.at.timeIntervalSince(start))).font(Theme.numeral(40, weight: .ultraLight)).tracking(-0.8)
                        Text(Format.date(c.at)).font(.system(size: 11)).foregroundStyle(Theme.ink3)
                    }
                }
            }

            stage
            lanesView
            transport
        }
        .padding(.horizontal, 40)
        .padding(.top, 54)
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
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.black.opacity(0.4))
                if let snap = snapshot, let file = snap.file {
                    SnapshotImage(url: store.snapshots(mission.id).appendingPathComponent(file))
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
                        .padding(18)
                } else {
                    VStack(spacing: 12) {
                        ZenithGlyph(live: true).frame(width: 34, height: 34)
                        Text("No cloud screen yet at this point").font(Theme.body(12.5)).foregroundStyle(Theme.ink3)
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 260, maxHeight: 440)

            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("Around this moment").padding(.bottom, 12)
                let lo = max(0, index - 5)
                let hi = max(lo, min(events.count, index + 7))
                ForEach(Array(events[lo..<hi].enumerated()), id: \.element.id) { offset, e in
                    let isNow = lo + offset == index
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(Theme.color(e.member)).frame(width: isNow ? 7 : 5, height: isNow ? 7 : 5)
                            .shadow(color: isNow ? Theme.color(e.member) : .clear, radius: 4)
                            .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 4 }
                        Text(e.text).font(e.kind == .tool ? Theme.mono(10.5) : Theme.body(12))
                            .foregroundStyle(isNow ? Theme.ink : Theme.ink3).lineLimit(isNow ? 5 : 1)
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .background(isNow ? Theme.glassStrong : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture { cursor = Double(lo + offset) }
                }
            }
            .padding(16)
            .frame(width: 330, alignment: .topLeading)
            .glass(radius: 20)
        }
    }

    private var lanesView: some View {
        VStack(spacing: 2) {
            ForEach(lanes, id: \.self) { lane in
                HStack(spacing: 14) {
                    MemberTag(member: lane).frame(width: 70, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.05)).frame(height: 4)
                            ForEach(laneEvents(lane)) { e in
                                Capsule()
                                    .fill(e.kind == .tool ? Theme.color(lane).opacity(0.45) : tickColor(e, lane))
                                    .frame(width: e.kind == .tool ? 1.5 : 3, height: e.kind == .tool ? 8 : 16)
                                    .shadow(color: e.kind == .tool ? .clear : tickColor(e, lane).opacity(0.8), radius: 3)
                                    .offset(x: x(e.at, geo.size.width))
                            }
                            if let c = current {
                                Rectangle().fill(Theme.ink).frame(width: 1, height: 30).offset(x: x(c.at, geo.size.width))
                            }
                        }
                        .frame(height: geo.size.height)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { v in seek(to: v.location.x / max(1, geo.size.width)) })
                    }
                    .frame(height: 30)
                }
            }
        }
        .padding(18)
        .glass(radius: 20)
    }

    private var transport: some View {
        HStack(spacing: 16) {
            Button {
                if index >= events.count - 1 { cursor = 0 }
                playing.toggle()
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.1, green: 0.07, blue: 0.03))
                    .frame(width: 40, height: 40)
                    .background(Theme.sun, in: Circle())
                    .shadow(color: Theme.sunGlow, radius: 12)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            Slider(value: $cursor, in: 0...Double(max(1, events.count - 1)))
                .tint(Theme.sun)
            Text("\(index + 1) / \(events.count)").font(Theme.numeral(13, weight: .light)).foregroundStyle(Theme.ink3)
                .frame(width: 84, alignment: .trailing)
        }
    }

    private func laneEvents(_ lane: Member) -> [TimelineEvent] {
        events.filter { $0.member == lane || (lane == .cloud && $0.member == .orbit) }
    }

    private func x(_ at: Date, _ width: CGFloat) -> CGFloat {
        CGFloat(at.timeIntervalSince(start) / span) * max(0, width - 3)
    }

    private func tickColor(_ e: TimelineEvent, _ lane: Member) -> Color {
        switch e.kind {
        case .error: return Theme.alert
        case .done: return Theme.good
        default: return Theme.color(lane)
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
