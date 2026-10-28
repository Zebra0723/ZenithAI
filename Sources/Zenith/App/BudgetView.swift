import SwiftUI
import ZenithCore

/// The Galaxy budget: the week's usage of the Max plan against the cap, what used it,
/// and what's waiting for room.
struct BudgetView: View {
    @ObservedObject private var store = Store.shared
    @ObservedObject private var commander = Commander.shared
    @State private var shown = ""

    var body: some View {
        Page(maxWidth: 900) {
            PageTitle(eyebrow: "Galaxy budget", title: "This week on the Max plan",
                      subtitle: "Every member runs on your Claude Max plan, never a paid API. The whole Galaxy stays under its cap; Zenith takes only the room that's left, runs heavy work overnight, and pauses before the cap rather than after.")

            if let r = commander.reading {
                meter(r)
                breakdown(r)
                calibration(r)
                others
                queue
            } else {
                Panel { HStack { ProgressView().controlSize(.small); Text("Measuring…").foregroundStyle(Theme.ink2) } }
            }
        }
        .task { await commander.refreshBudget(force: true) }
    }

    private func meter(_ r: BudgetReading) -> some View {
        Panel(padding: 26) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Format.percent(r.usedPercent)).font(Theme.numeral(44, weight: .semibold)).tracking(-1)
                    Text("of the weekly limit used").font(Theme.body(14)).foregroundStyle(Theme.ink2)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(Format.percent(r.roomPercent) + " left under the cap").font(.system(size: 13, weight: .semibold))
                        Text("Resets \(Format.date(r.weekEnd))").font(Theme.mono(10.5)).foregroundStyle(Theme.ink3)
                    }
                }
                WeekBar(reading: r)
                HStack(spacing: 18) {
                    legend(Theme.ink, "This Mac")
                    legend(Theme.calm, "Zenith cloud")
                    legend(Theme.ink3.opacity(0.5), "Other members (estimated)")
                    Spacer()
                    Text(r.calibrated ? "Calibrated this week" : "Not calibrated this week")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(r.calibrated ? Theme.good : Theme.sunDeep)
                }
            }
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(text).font(.system(size: 11)).foregroundStyle(Theme.ink2)
        }
    }

    private func breakdown(_ r: BudgetReading) -> some View {
        Panel(padding: 0) {
            VStack(spacing: 0) {
                row("Claude Code on this Mac", "Zenith's sandbox runs, and anything else using the plan here", r.macPercent)
                Rule()
                row("Zenith in the cloud", "Missions on Claude Code cloud sessions", r.cloudPercent)
                Rule()
                row("Other members", "Comet, Nova and Orbit, by the estimates below, so far this week", r.othersPercent)
                Rule()
                row("Zenith alone", "Every mission this week, sandbox and cloud", r.zenithPercent, quiet: true)
            }
        }
    }

    private func row(_ title: String, _ detail: String, _ value: Double, quiet: Bool = false) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(quiet ? Theme.ink2 : Theme.ink)
                Text(detail).font(Theme.body(11.5)).foregroundStyle(Theme.ink3)
            }
            Spacer()
            Text(Format.percent(value)).font(Theme.numeral(15, weight: .semibold)).foregroundStyle(quiet ? Theme.ink2 : Theme.ink)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func calibration(_ r: BudgetReading) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow("Calibrate")
                Text("Anthropic doesn't publish the limit in tokens, so Zenith measures usage in its own units and needs one reading of the real thing. Open Claude's usage settings (or /usage in Claude Code), and type the weekly percentage it shows.")
                    .font(Theme.body(12.5)).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    TextField("e.g. 18", text: $shown).zenithField(mono: true).frame(width: 110)
                    Text("% used right now").font(Theme.body(12.5)).foregroundStyle(Theme.ink2)
                    Button("Calibrate") {
                        if let v = Double(shown.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)), v >= 0, v <= 100 {
                            commander.calibrate(shownPercent: v)
                            shown = ""
                        }
                    }
                    .buttonStyle(ZenithButtonStyle(kind: .primary))
                    .disabled(Double(shown.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) == nil)
                    Spacer()
                }
                HStack(spacing: 10) {
                    Text("Units per 1% of the week").font(Theme.body(12)).foregroundStyle(Theme.ink2)
                    TextField("", value: $store.settings.budget.unitsPerPercent, format: .number.precision(.fractionLength(0...2)))
                        .zenithField(mono: true).frame(width: 90)
                    Text("Raise it if Zenith reads higher than Claude does; lower it if lower.")
                        .font(Theme.body(11.5)).foregroundStyle(Theme.ink3)
                }
            }
        }
    }

    private var others: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow("The other members, per week")
                Text("This Mac can't measure Comet (it runs on its server) or Nova (on its own key until it moves to the plan). These are the plan's ballpark shares; adjust them to what you see.")
                    .font(Theme.body(12.5)).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
                ForEach(["comet", "nova", "orbit", "nebula"], id: \.self) { key in
                    HStack {
                        Text(key.capitalized).font(.system(size: 13, weight: .medium)).frame(width: 80, alignment: .leading)
                        Slider(value: Binding(get: { store.settings.budget.others[key] ?? 0 },
                                              set: { store.settings.budget.others[key] = ($0 * 2).rounded() / 2 }), in: 0...30)
                            .tint(Theme.ink)
                        Text(Format.percent(store.settings.budget.others[key] ?? 0)).font(Theme.mono(11.5)).frame(width: 52, alignment: .trailing)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var queue: some View {
        let waiting = store.missions.filter { $0.status == .queued }
        if !waiting.isEmpty {
            Panel(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow("Waiting for room").padding(20)
                    ForEach(waiting) { m in
                        Rule()
                        HStack {
                            Text(m.title).font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text(m.statusNote).font(Theme.body(12)).foregroundStyle(Theme.ink2).multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                }
            }
        }
    }
}

/// The week from 0 to 100%: what each part of the Galaxy used, and the cap.
struct WeekBar: View {
    let reading: BudgetReading

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let mac = min(1, reading.macPercent / 100)
            let cloud = min(1 - mac, reading.cloudPercent / 100)
            let calibratedExtra = max(0, reading.usedPercent - reading.macPercent - reading.cloudPercent - reading.othersPercent) / 100
            let others = min(1 - mac - cloud, reading.othersPercent / 100 + calibratedExtra)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.raised)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                HStack(spacing: 0) {
                    Rectangle().fill(Theme.ink).frame(width: w * mac)
                    Rectangle().fill(Theme.calm).frame(width: w * max(0, cloud))
                    Rectangle().fill(Theme.ink3.opacity(0.5)).frame(width: w * max(0, others))
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                // The cap.
                VStack(spacing: 4) {
                    Rectangle().fill(Theme.sun).frame(width: 2, height: 34)
                }
                .offset(x: w * reading.capPercent / 100 - 1)
                Text("Cap \(Int(reading.capPercent))%").font(Theme.mono(10, weight: .semibold)).foregroundStyle(Theme.sunDeep)
                    .offset(x: w * reading.capPercent / 100 + 6, y: -26)
            }
        }
        .frame(height: 22)
        .padding(.top, 18)
    }
}
