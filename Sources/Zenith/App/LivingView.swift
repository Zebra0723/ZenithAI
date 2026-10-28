import SwiftUI
import ZenithCore

/// Finished results Zenith keeps working and up to date, silently. Shown here and on the
/// board only: a living mission never sends anything.
struct LivingView: View {
    @ObservedObject var navigation: Navigation
    @ObservedObject private var store = Store.shared
    @ObservedObject private var commander = Commander.shared

    private var living: [Mission] { store.missions.filter { $0.living != nil } }

    var body: some View {
        Page(maxWidth: 940) {
            PageTitle(eyebrow: "Living missions", title: "Kept alive, quietly.",
                      subtitle: "When a result should keep working after it's done (a site, prices, a schedule), Zenith checks it on a cadence and fixes what needs it. No messages, just a line on the board.")
            if living.isEmpty {
                Panel(padding: 0) {
                    EmptyState(title: "No living missions", detail: "A forecast says when a mission will be kept alive afterwards. Those land here once they're done.")
                }
            }
            ForEach(living) { m in
                LivingCard(mission: m, navigation: navigation, running: commander.live[m.id] != nil)
            }
        }
    }
}

private struct LivingCard: View {
    let mission: Mission
    @ObservedObject var navigation: Navigation
    let running: Bool
    @ObservedObject private var commander = Commander.shared

    var body: some View {
        if let plan = mission.living {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Eyebrow(plan.enabled ? "\(plan.cadence.title) upkeep" : "Paused", color: plan.enabled ? Theme.calm : Theme.ink3)
                            if running { PulseDot(color: Theme.calm) }
                        }
                        Text(mission.title).font(Theme.display(26)).tracking(-0.4)
                        Text(plan.task).font(Theme.body(13.5)).lineSpacing(2).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Eyebrow("Next check")
                        Text(plan.enabled ? Format.time(plan.nextRun) : "Off").font(Theme.numeral(30, weight: .ultraLight))
                        if plan.enabled {
                            Text(Format.date(plan.nextRun)).font(.system(size: 10.5)).foregroundStyle(Theme.ink3)
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 24)
                .padding(.bottom, 18)

                if !plan.runs.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(plan.runs.suffix(30).enumerated()), id: \.offset) { _, run in
                            Capsule().fill(run.ok ? Theme.calm : Theme.alert)
                                .frame(width: 5, height: 18)
                                .opacity(0.85)
                                .help("\(Format.date(run.at)): \(run.note)")
                        }
                        Spacer()
                        if let last = plan.runs.last {
                            Text(last.note).font(Theme.body(12)).foregroundStyle(Theme.ink2).lineLimit(1)
                                .frame(maxWidth: 380, alignment: .trailing)
                        }
                    }
                    .padding(.horizontal, 26)
                    .padding(.bottom, 18)
                }

                HStack(spacing: 14) {
                    ZenithToggle(isOn: Binding(get: { plan.enabled }, set: { commander.setLiving(mission.id, enabled: $0) }))
                    Picker("", selection: Binding(get: { plan.cadence }, set: { commander.setLiving(mission.id, cadence: $0) })) {
                        ForEach(Cadence.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 230)
                    Text("\(plan.runs.count) \(plan.runs.count == 1 ? "check" : "checks")").font(.system(size: 11.5)).foregroundStyle(Theme.ink3)
                    Spacer()
                    Button("Open") { navigation.open(mission.id) }.buttonStyle(ZenithButtonStyle())
                    Button("Check now") { commander.runLiving(mission.id) }
                        .buttonStyle(ZenithButtonStyle(kind: .primary))
                        .disabled(running)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .background(Color.black.opacity(0.16))
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .glass(radius: 24, tint: running ? Theme.calm : nil)
        }
    }
}
