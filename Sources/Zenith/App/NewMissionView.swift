import SwiftUI
import ZenithCore

/// The goal goes in, the forecast comes out, and one thumbs up launches it.
struct NewMissionView: View {
    @ObservedObject var navigation: Navigation
    @ObservedObject private var store = Store.shared
    @State private var brief = ""
    @State private var context = ""
    @State private var showContext = false
    @FocusState private var focused: Bool
    /// The mission this page is forecasting, once the brief is in.
    @State private var draftID: String?

    private static let examples = [
        ("Build", "A site for my bakery with the menu and opening hours, put online"),
        ("Decide", "The three best e-bikes under $2,000 for a hilly commute, and pick one"),
        ("Sort", "My Downloads folder: file every PDF by what it is"),
        ("Coordinate", "Saturday's dinner: ask Sam and Priya what time works and book the table"),
    ]

    var body: some View {
        Page(maxWidth: 900) {
            PageTitle(eyebrow: "New mission", title: "What should the Galaxy get done?",
                      subtitle: "Say it the way you'd say it to a person. Zenith won't ask questions first: it decides what it can, writes its assumptions down, and saves anything only you can answer for one batch at the end.")

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
                    showContext = !m.context.isEmpty
                    Commander.shared.delete(id)
                    draftID = nil
                }
            } else {
                composer
            }
        }
    }

    private var ready: Bool { brief.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8 }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    if brief.isEmpty {
                        Text("A big goal: hours, days or weeks of work…")
                            .font(Theme.display(24))
                            .foregroundStyle(Theme.ink3)
                            .padding(.horizontal, 26)
                            .padding(.vertical, 24)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $brief)
                        .font(Theme.display(24))
                        .lineSpacing(4)
                        .foregroundStyle(Theme.ink)
                        .scrollContentBackground(.hidden)
                        .focused($focused)
                        .padding(.horizontal, 21)
                        .padding(.vertical, 20)
                }
                .frame(minHeight: 180)

                if showContext {
                    Rule().padding(.horizontal, 24)
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow("Context")
                        TextEditor(text: $context)
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.ink2)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 80)
                    }
                    .padding(.horizontal, 26)
                    .padding(.vertical, 16)
                }

                HStack(spacing: 10) {
                    Button { withAnimation(.easeOut(duration: 0.15)) {
                        showContext.toggle()
                        if !showContext { context = "" }
                    } } label: {
                        Label(showContext ? "Remove context" : "Add context", systemImage: showContext ? "minus" : "text.append")
                    }
                    .buttonStyle(ZenithButtonStyle())
                    Spacer()
                    Text("Opus writes the forecast. Nothing runs yet.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.ink3)
                    Button {
                        draftID = Commander.shared.create(brief: brief, context: context)
                        brief = ""
                        context = ""
                        showContext = false
                    } label: {
                        HStack(spacing: 8) {
                            Text("Forecast")
                            Image(systemName: "arrow.right")
                        }
                    }
                    .buttonStyle(ZenithButtonStyle(kind: .primary))
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!ready)
                }
                .padding(16)
                .background(Color.black.opacity(0.14))
            }
            .glass(radius: 24, tint: focused ? Theme.sun : nil)
            .animation(.easeOut(duration: 0.2), value: focused)
            .onAppear { focused = true }

            VStack(alignment: .leading, spacing: 12) {
                Eyebrow("Try one")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(Self.examples, id: \.1) { kind, text in
                        ExampleChip(kind: kind, text: text) { brief = text }
                    }
                }
            }

            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 14)).foregroundStyle(Theme.ink3)
                Text("Brief Zenith from anywhere: text Comet \"Zenith: …\", ask Orbit or Nova, or say \"make it a mission\" in any conversation. Ask any of them \"how's my mission?\" for the status.")
                    .font(Theme.body(12.5)).lineSpacing(2).foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 6)
        }
    }
}

private struct ExampleChip: View {
    let kind: String
    let text: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                Eyebrow(kind, color: hovering ? Theme.sunSoft : Theme.ink3)
                Text(text).font(Theme.body(13)).lineSpacing(2).foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
            .glass(radius: 16, strong: hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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
            Panel(padding: 34) {
                HStack(spacing: 22) {
                    ForecastingMark().frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Writing the forecast").font(Theme.display(22))
                        Text(mission.brief).font(Theme.body(13)).foregroundStyle(Theme.ink2).lineLimit(2)
                    }
                }
            }
        } else if mission.status == .failed {
            Panel(padding: 26, tint: Theme.alert) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("The forecast didn't work").font(Theme.display(22))
                    Text(mission.statusNote).font(Theme.body(13)).foregroundStyle(Theme.ink2)
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
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow("Forecast", color: Theme.sunSoft)
                Text(f.title).font(Theme.display(34)).tracking(-0.6)
                if !f.summary.isEmpty {
                    Text(f.summary).font(Theme.body(14)).lineSpacing(3).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 30)
            .padding(.bottom, 24)

            HStack(spacing: 0) {
                figure("Time", Format.hours(f.hours))
                divider
                figure("Of the week", Format.percent(f.usagePercent))
                divider
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow("Members")
                    HStack(spacing: 12) {
                        ForEach([Member.zenith] + f.members, id: \.self) { MemberTag(member: $0) }
                    }
                }
                .padding(.horizontal, 30)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 20)
            .background(Color.black.opacity(0.14))

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(f.steps.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .top, spacing: 18) {
                        ZStack {
                            Circle().fill(Color(red: 0.06, green: 0.07, blue: 0.14))
                            Circle().fill(Theme.color(s.member).opacity(0.16))
                            Circle().strokeBorder(Theme.color(s.member).opacity(0.7), lineWidth: 1)
                            Text("\(i + 1)").font(Theme.numeral(11, weight: .medium)).foregroundStyle(Theme.ink)
                        }
                        .frame(width: 26, height: 26)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(s.title).font(.system(size: 14, weight: .semibold))
                                Spacer(minLength: 10)
                                MemberTag(member: s.member)
                                Text(s.model.name).font(Theme.mono(10.5)).foregroundStyle(Theme.ink3).frame(width: 78, alignment: .trailing)
                            }
                            if !s.detail.isEmpty {
                                Text(s.detail).font(Theme.body(12.5)).lineSpacing(2).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.top, 3)
                        .padding(.bottom, 20)
                    }
                }
            }
            // The flight path joining the steps.
            .background(alignment: .leading) {
                Rectangle().fill(Theme.lineStrong).frame(width: 1).padding(.leading, 12.5).padding(.vertical, 20)
            }
            .padding(.horizontal, 30)
            .padding(.top, 26)
            .padding(.bottom, 6)

            if !f.needsYou.isEmpty || !f.assumptions.isEmpty || f.living != nil {
                HStack(alignment: .top, spacing: 30) {
                    if !f.needsYou.isEmpty { list("Needs you once, at the end", f.needsYou, Theme.alert) }
                    if !f.assumptions.isEmpty { list("Assumptions", f.assumptions, Theme.ink3) }
                    if let living = f.living { list("Kept alive afterwards", ["\(living) (\((f.cadence ?? .daily).title.lowercased()))"], Theme.calm) }
                }
                .padding(30)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.12))
            }

            HStack(spacing: 12) {
                Image(systemName: "clock").font(.system(size: 12)).foregroundStyle(Theme.ink3)
                Text(commander.launchPreview(mission))
                    .font(Theme.body(12.5)).foregroundStyle(Theme.ink2)
                Spacer()
                if let edit { Button("Edit the brief", action: edit).buttonStyle(ZenithButtonStyle()) }
                Button("Discard", action: discard).buttonStyle(ZenithButtonStyle())
                Button(action: launch) {
                    Label("Launch", systemImage: "hand.thumbsup.fill")
                }
                .buttonStyle(ZenithButtonStyle(kind: .primary))
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .overlay(alignment: .top) { Rule() }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .glass(radius: 24)
    }

    private var divider: some View { Rectangle().fill(Theme.line).frame(width: 1, height: 52) }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(label)
            Text(value).font(Theme.numeral(30, weight: .ultraLight)).tracking(-0.5)
        }
        .padding(.horizontal, 30)
    }

    private func list(_ title: String, _ items: [String], _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(title)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Circle().fill(color).frame(width: 4, height: 4).alignmentGuide(.firstTextBaseline) { d in d[.bottom] + 1 }
                    Text(item).font(Theme.body(12.5)).lineSpacing(2).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// While Opus forecasts: the sun circling the horizon.
private struct ForecastingMark: View {
    @State private var turn = false

    var body: some View {
        ZStack {
            Circle().stroke(Theme.line, lineWidth: 1.5)
            Circle()
                .trim(from: 0, to: 0.22)
                .stroke(Theme.sun, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .shadow(color: Theme.sun, radius: 4)
                .rotationEffect(.degrees(turn ? 360 : 0))
            ZenithGlyph(live: true).frame(width: 20, height: 20)
        }
        .onAppear { withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { turn = true } }
    }
}
