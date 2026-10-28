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
        Page(maxWidth: 900) {
            PageTitle(eyebrow: "Living missions", title: "Kept alive",
                      subtitle: "When a result should keep working after it's done (a site, prices, a schedule), Zenith checks it on a cadence and fixes what needs it. Quietly: no messages, just a line on the board.")
            if living.isEmpty {
                Panel { EmptyState(title: "No living missions", detail: "A forecast says when a mission will be kept alive afterwards. Those land here once they're done.") }
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
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(mission.title).font(Theme.display(16))
                            if running { PulseDot() }
                        }
                        Text(plan.task).font(Theme.body(13)).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    ZenithToggle(isOn: Binding(get: { plan.enabled }, set: { commander.setLiving(mission.id, enabled: $0) }))
                }
                .padding(20)

                HStack(spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow("Cadence")
                        Picker("", selection: Binding(get: { plan.cadence }, set: { commander.setLiving(mission.id, cadence: $0) })) {
                            ForEach(Cadence.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 230)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow("Next check")
                        Text(plan.enabled ? Format.date(plan.nextRun) : "Off").font(Theme.mono(12))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow("Checks")
                        Text("\(plan.runs.count)").font(Theme.mono(12))
                    }
                    Spacer()
                    Button("Open") { navigation.open(mission.id) }.buttonStyle(ZenithButtonStyle())
                    Button("Check now") { commander.runLiving(mission.id) }
                        .buttonStyle(ZenithButtonStyle(kind: .primary))
                        .disabled(running)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)

                if !plan.runs.isEmpty {
                    Rule()
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(plan.runs.suffix(5).reversed().enumerated()), id: \.offset) { _, run in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Circle().fill(run.ok ? Theme.good : Theme.alert).frame(width: 6, height: 6)
                                Text(Format.date(run.at)).font(Theme.mono(10.5)).foregroundStyle(Theme.ink3).frame(width: 130, alignment: .leading)
                                Text(run.note).font(Theme.body(12)).foregroundStyle(Theme.ink2).lineLimit(2)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(running ? Theme.sun.opacity(0.6) : Theme.line, lineWidth: 1))
        }
    }
}
