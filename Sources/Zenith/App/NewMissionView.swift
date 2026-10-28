import SwiftUI
import ZenithCore

/// The goal goes in, the forecast comes out, and one thumbs up launches it.
struct NewMissionView: View {
    @ObservedObject var navigation: Navigation
    @ObservedObject private var store = Store.shared
    @State private var brief = ""
    @State private var context = ""
    @State private var showContext = false
    /// The mission this page is forecasting, once the brief is in.
    @State private var draftID: String?

    private static let examples = [
        "Build a site for my bakery with the menu and opening hours, and put it online",
        "Research the three best e-bikes under $2,000 for a hilly commute and pick one",
        "Sort my Downloads folder and file every PDF by what it is",
        "Plan Saturday's dinner: ask Sam and Priya what time works and book the table",
    ]

    var body: some View {
        Page(maxWidth: 860) {
            PageTitle(eyebrow: "New mission", title: "What should the Galaxy get done?",
                      subtitle: "Say the goal the way you'd say it to a person. Zenith won't ask questions first: it decides what it can, writes down its assumptions, and saves anything only you can answer for one batch at the end.")

            if let id = draftID, let m = store.mission(id) {
                ForecastPanel(mission: m) {
                    Commander.shared.launch(id)
                    draftID = nil
                    navigation.open(id)
                } discard: {
                    Commander.shared.delete(id)
                    draftID = nil
                } edit: {
                    brief = m.brief
                    context = m.context
                    Commander.shared.delete(id)
                    draftID = nil
                }
            } else {
                composer
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 18) {
            ZStack(alignment: .topLeading) {
                if brief.isEmpty {
                    Text("A big goal: hours, days or weeks of work")
                        .font(Theme.body(17))
                        .foregroundStyle(Theme.ink3)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $brief)
                    .font(Theme.body(17))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 14)
            }
            .frame(minHeight: 150)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.lineStrong, lineWidth: 1))

            if showContext {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("Context")
                    TextEditor(text: $context)
                        .font(Theme.body(13))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 90)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                    Text("Paste a conversation, notes or links. It goes into the forecast and every step.")
                        .font(Theme.body(11.5)).foregroundStyle(Theme.ink3)
                }
            }

            HStack(spacing: 10) {
                Button(showContext ? "Remove context" : "Add context") {
                    showContext.toggle()
                    if !showContext { context = "" }
                }
                .buttonStyle(ZenithButtonStyle())
                Spacer()
                Text("Opus writes the forecast. Nothing runs yet.")
                    .font(Theme.body(11.5)).foregroundStyle(Theme.ink3)
                Button {
                    draftID = Commander.shared.create(brief: brief, context: context)
                    brief = ""
                    context = ""
                    showContext = false
                } label: {
                    Label("Forecast", systemImage: "arrow.right")
                }
                .buttonStyle(ZenithButtonStyle(kind: .primary))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(brief.trimmingCharacters(in: .whitespacesAndNewlines).count < 8)
            }

            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("For example")
                ForEach(Self.examples, id: \.self) { example in
                    Button { brief = example } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.turn.down.right").font(.system(size: 10)).foregroundStyle(Theme.ink3)
                            Text(example).font(Theme.body(13)).foregroundStyle(Theme.ink2)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 10)

            Panel(padding: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "point.3.connected.trianglepath.dotted").foregroundStyle(Theme.ink3)
                    Text("You can also brief Zenith from anywhere: text Comet \"Zenith: …\", ask Orbit or Nova, or say \"make it a mission\" in any conversation. Ask any of them \"how's my mission?\" for the status.")
                        .font(Theme.body(12.5)).foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A forecast: the plan, who it uses, the time, the usage, and what will need the user.
struct ForecastPanel: View {
    let mission: Mission
    let launch: () -> Void
    let discard: () -> Void
    var edit: (() -> Void)?
    @ObservedObject private var commander = Commander.shared

    var body: some View {
        if mission.status == .forecasting {
            Panel(padding: 28) {
                HStack(spacing: 14) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Writing the forecast").font(Theme.display(15))
                        Text(mission.brief).font(Theme.body(12.5)).foregroundStyle(Theme.ink2).lineLimit(2)
                    }
                }
            }
        } else if mission.status == .failed {
            Panel {
                VStack(alignment: .leading, spacing: 10) {
                    Text("The forecast didn't work").font(Theme.display(15))
                    Text(mission.statusNote).font(Theme.body(12.5)).foregroundStyle(Theme.alert)
                    HStack {
                        Button("Try again") { commander.forecast(mission.id) }.buttonStyle(ZenithButtonStyle(kind: .primary))
                        Button("Discard", action: discard).buttonStyle(ZenithButtonStyle())
                    }
                }
            }
        } else if let f = mission.forecast {
            forecast(f)
        }
    }

    private func forecast(_ f: Forecast) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("Forecast", color: Theme.sunDeep)
                Text(f.title).font(Theme.display(22))
                if !f.summary.isEmpty {
                    Text(f.summary).font(Theme.body(13.5)).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)

            HStack(spacing: 0) {
                figure("Time", Format.hours(f.hours))
                divider
                figure("Usage", Format.percent(f.usagePercent) + " of the week")
                divider
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("Members")
                    HStack(spacing: 6) {
                        ForEach([Member.zenith] + f.members, id: \.self) { Pill(text: $0.name, color: Theme.ink2) }
                    }
                }
                .padding(.horizontal, 24)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 16)
            .overlay(alignment: .top) { Rule() }
            .overlay(alignment: .bottom) { Rule() }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(f.steps.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .top, spacing: 14) {
                        Text(String(format: "%02d", i + 1)).font(Theme.mono(11)).foregroundStyle(Theme.ink3).frame(width: 22, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(s.title).font(.system(size: 13.5, weight: .semibold))
                            if !s.detail.isEmpty {
                                Text(s.detail).font(Theme.body(12.5)).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 10)
                        Text(s.member.name).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.ink2)
                        Text(s.model.name).font(Theme.mono(10.5)).foregroundStyle(Theme.ink3).frame(width: 74, alignment: .trailing)
                    }
                    .padding(.vertical, 11)
                    if i < f.steps.count - 1 { Rule() }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 6)

            if !f.needsYou.isEmpty || !f.assumptions.isEmpty || f.living != nil {
                HStack(alignment: .top, spacing: 28) {
                    if !f.needsYou.isEmpty { list("Will need you, once, at the end", f.needsYou) }
                    if !f.assumptions.isEmpty { list("Assumptions", f.assumptions) }
                    if let living = f.living { list("Kept alive afterwards", ["\(living) (\((f.cadence ?? .daily).title.lowercased()))"]) }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.raised)
                .overlay(alignment: .top) { Rule() }
            }

            HStack(spacing: 10) {
                Text(commander.launchPreview(mission))
                    .font(Theme.body(12)).foregroundStyle(Theme.ink2)
                Spacer()
                if let edit { Button("Edit the brief", action: edit).buttonStyle(ZenithButtonStyle()) }
                Button("Discard", action: discard).buttonStyle(ZenithButtonStyle())
                Button(action: launch) {
                    Label("Launch", systemImage: "hand.thumbsup")
                }
                .buttonStyle(ZenithButtonStyle(kind: .primary))
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(20)
            .overlay(alignment: .top) { Rule() }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var divider: some View { Rectangle().fill(Theme.line).frame(width: 1, height: 38) }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(label)
            Text(value).font(Theme.numeral(15, weight: .semibold))
        }
        .padding(.horizontal, 24)
    }

    private func list(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(title)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Rectangle().fill(Theme.ink3).frame(width: 8, height: 1)
                    Text(item).font(Theme.body(12.5)).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
