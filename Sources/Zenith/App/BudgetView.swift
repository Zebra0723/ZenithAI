import SwiftUI
import ZenithCore

/// The Galaxy budget: the week's usage of the Max plan against the cap, what used it,
/// and what's waiting for room.
struct BudgetView: View {
    @ObservedObject private var store = Store.shared
    @ObservedObject private var commander = Commander.shared
    @State private var shown = ""

    var body: some View {
        Page(maxWidth: 960) {
            PageTitle(eyebrow: "Galaxy budget", title: "This week on the Max plan.",
                      subtitle: "Every member runs on your Claude Max plan, never a paid API. The whole Galaxy stays under its cap; Zenith takes only the room that's left, runs heavy work overnight, and pauses before the cap rather than after.")

            if let r = commander.reading {
                hero(r)
                calibration
                others
                queue
            } else {
                Panel { HStack(spacing: 12) { ProgressView().controlSize(.small); Text("Measuring…").foregroundStyle(Theme.ink2) } }
            }
        }
        .task { await commander.refreshBudget(force: true) }
    }

    private func hero(_ r: BudgetReading) -> some View {
        HStack(alignment: .center, spacing: 40) {
            SunDial(value: r.usedPercent / 100, cap: r.capPercent / 100, lineWidth: 12,
                    label: Format.percent(r.usedPercent), caption: "of the week")
                .frame(width: 230, height: 230)
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Format.percent(r.roomPercent)).font(Theme.numeral(48, weight: .ultraLight)).tracking(-1)
                    Text("left under the \(Int(r.capPercent))% cap · resets \(Format.date(r.weekEnd))")
                        .font(Theme.body(13)).foregroundStyle(Theme.ink2)
                }
                VStack(spacing: 0) {
                    row(Theme.ink, "Claude Code on this Mac", "Zenith's sandbox runs, and anything else on the plan here", r.macPercent)
                    Rule()
                    row(Theme.color(.cloud), "Zenith in the cloud", "Missions on Claude Code cloud sessions", r.cloudPercent)
                    Rule()
                    row(Theme.ink3, "Other members", "Comet, Nova and Orbit, estimated so far this week", r.othersPercent)
                    Rule()
                    row(Theme.sun, "Zenith alone", "Every mission this week, sandbox and cloud", r.zenithPercent)
                }
                HStack(spacing: 8) {
                    Circle().fill(r.calibrated ? Theme.good : Theme.sun).frame(width: 6, height: 6)
                    Text(r.calibrated ? "Calibrated this week" : "Not calibrated this week: the reading is an estimate")
                        .font(.system(size: 11.5, weight: .medium)).foregroundStyle(r.calibrated ? Theme.good : Theme.sunSoft)
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 26)
    }

    private func row(_ color: Color, _ title: String, _ detail: String, _ value: Double) -> some View {
        HStack(spacing: 12) {
            Capsule().fill(color).frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(Theme.ink3)
            }
            Spacer()
            Text(Format.percent(value)).font(Theme.numeral(20, weight: .light))
        }
        .padding(.vertical, 9)
    }

    private var calibration: some View {
        Panel(padding: 26) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Calibrate").font(Theme.display(22))
                Text("Anthropic doesn't publish the limit in tokens, so Zenith measures in its own units and needs one reading of the real thing. Open Claude's usage settings (or /usage in Claude Code) and type the weekly percentage it shows.")
                    .font(Theme.body(13)).lineSpacing(2).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    TextField("18", text: $shown).zenithField(mono: true).frame(width: 90)
                    Text("% used right now").font(Theme.body(13)).foregroundStyle(Theme.ink2)
                    Button("Calibrate") {
                        if let v = parsed, v >= 0, v <= 100 {
                            commander.calibrate(shownPercent: v)
                            shown = ""
                        }
                    }
                    .buttonStyle(ZenithButtonStyle(kind: .primary))
                    .disabled(parsed == nil)
                    Spacer()
                    Text("Units per 1%").font(.system(size: 11.5)).foregroundStyle(Theme.ink3)
                    TextField("", value: $store.settings.budget.unitsPerPercent, format: .number.precision(.fractionLength(0...2)))
                        .zenithField(mono: true).frame(width: 80)
                }
            }
        }
    }

    private var parsed: Double? {
        Double(shown.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
    }

    private var others: some View {
        Panel(padding: 26) {
            VStack(alignment: .leading, spacing: 16) {
                Text("The other members, per week").font(Theme.display(22))
                Text("This Mac can't measure Comet (it runs on its server) or Nova (on its own key until it moves to the plan). These are the plan's ballpark shares; adjust them to what you see.")
                    .font(Theme.body(13)).lineSpacing(2).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
                ForEach([Member.comet, .nova, .orbit, .nebula], id: \.self) { member in
                    let key = member.rawValue
                    HStack(spacing: 16) {
                        MemberTag(member: member).frame(width: 80, alignment: .leading)
                        Slider(value: Binding(get: { store.settings.budget.others[key] ?? 0 },
                                              set: { store.settings.budget.others[key] = ($0 * 2).rounded() / 2 }), in: 0...30)
                            .tint(Theme.color(member))
                        Text(Format.percent(store.settings.budget.others[key] ?? 0)).font(Theme.numeral(15, weight: .light))
                            .frame(width: 56, alignment: .trailing)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var queue: some View {
        let waiting = store.missions.filter { $0.status == .queued }
        if !waiting.isEmpty {
            Panel(padding: 26) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Waiting for room").font(Theme.display(22))
                    ForEach(waiting) { m in
                        HStack(alignment: .firstTextBaseline) {
                            Text(m.title).font(.system(size: 13.5, weight: .semibold))
                            Spacer()
                            Text(m.statusNote).font(Theme.body(12)).foregroundStyle(Theme.ink2).multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
        }
    }
}
