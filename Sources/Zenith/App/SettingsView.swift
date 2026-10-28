import AppKit
import ServiceManagement
import SwiftUI
import ZenithCore

struct SettingsView: View {
    @ObservedObject private var store = Store.shared
    @ObservedObject private var commander = Commander.shared
    @ObservedObject private var connector = Connector.shared
    @State private var newContact = ""
    @State private var claudeFound: String?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Page(maxWidth: 860) {
            PageTitle(eyebrow: "Settings", title: "How Zenith runs the Galaxy")

            section("The cloud computer") {
                row("Where missions run", "Claude Code cloud sessions are part of the Max plan and keep running with the Mac off. Zenith uses them only after the check below passes; until then, an isolated sandbox on this Mac.") {
                    Picker("", selection: $store.settings.backend) {
                        Text("Sandbox on this Mac").tag(Backend.sandbox)
                        Text("Claude Code cloud").tag(Backend.cloud)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 290)
                }
                if store.settings.backend == .cloud {
                    row("Cloud check", cloudLine) {
                        Button(commander.cloudCheck == .checking ? "Checking…" : "Run the check") { commander.verifyCloud() }
                            .buttonStyle(ZenithButtonStyle(kind: store.settings.cloudVerifiedAt == nil ? .primary : .quiet))
                            .disabled(commander.cloudCheck == .checking)
                    }
                }
                row("Sandbox the worker", "On this Mac, the worker can write only to its mission's workspace, Claude Code's own files and caches, and can't read Mail, Messages, Documents, Desktop or Pictures. Nova does what needs the Mac.") {
                    ZenithToggle(isOn: $store.settings.sandboxed)
                }
                row("Claude Code", claudeLine) {
                    TextField("Found automatically", text: $store.settings.claudePath).zenithField(mono: true).frame(width: 240)
                }
            }

            section("Galaxy budget") {
                row("Cap", "The whole Galaxy stays under this share of the weekly Max limit. Zenith runs only when there's room under it.") {
                    HStack(spacing: 10) {
                        Slider(value: $store.settings.budget.capPercent, in: 10...90, step: 5).tint(Theme.ink).frame(width: 170)
                        Text("\(Int(store.settings.budget.capPercent))%").font(Theme.mono(12, weight: .semibold)).frame(width: 40, alignment: .trailing)
                    }
                }
                row("Heavy work overnight", "Missions forecast at or above the heavy line wait for the overnight window, when the limit would otherwise go unused.") {
                    ZenithToggle(isOn: $store.settings.budget.preferOvernight)
                }
                row("Overnight window", "Local time.") {
                    HStack(spacing: 8) {
                        hourPicker($store.settings.budget.overnightStart)
                        Text("to").foregroundStyle(Theme.ink2)
                        hourPicker($store.settings.budget.overnightEnd)
                    }
                }
                row("Heavy line", "A mission forecast at this share of the week or more counts as heavy.") {
                    Stepper(value: $store.settings.budget.heavyPercent, in: 1...30, step: 1) {
                        Text("\(Int(store.settings.budget.heavyPercent))%").font(Theme.mono(12))
                    }
                }
                row("Missions at once", "The most that run in parallel. The governor queues them sooner when usage is tight.") {
                    Stepper(value: $store.settings.maxParallel, in: 1...6) {
                        Text("\(store.settings.maxParallel)").font(Theme.mono(12))
                    }
                }
                row("Week resets", "When Claude's weekly limit starts over for your account.") {
                    HStack(spacing: 8) {
                        Picker("", selection: $store.settings.budget.resetWeekday) {
                            ForEach(1...7, id: \.self) { d in Text(Calendar.current.weekdaySymbols[d - 1]).tag(d) }
                        }
                        .labelsHidden().frame(width: 130)
                        hourPicker($store.settings.budget.resetHour)
                    }
                }
            }

            section("Your rules") {
                row("Nova acts on the Mac", "Anytime during a mission, pausing the instant you touch the mouse or keyboard.") {
                    ZenithToggle(isOn: $store.settings.useNova)
                }
                row("Comet texts during missions", "You and the people below, without asking. Anyone else needs your thumbs up first.") {
                    ZenithToggle(isOn: $store.settings.useComet)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("No-approval allowlist").font(.system(size: 13.5, weight: .semibold))
                    ForEach(store.settings.allowlist, id: \.self) { contact in
                        HStack {
                            Text(contact).font(Theme.mono(12))
                            Spacer()
                            Button { store.settings.allowlist.removeAll { $0 == contact } } label: {
                                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.ink3)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    HStack(spacing: 8) {
                        TextField("Name, phone number or email", text: $newContact).zenithField().onSubmit(addContact)
                        Button("Add", action: addContact).buttonStyle(ZenithButtonStyle())
                            .disabled(newContact.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(.vertical, 6)
                row("Thumbs up with Nebula", "Launches and yes-or-no questions also go to Galaxy Link, so Nebula can arm its camera for a thumbs up or down.") {
                    ZenithToggle(isOn: $store.settings.nebulaApprovals)
                }
                row("The done text", "One Comet text when a mission is done. Nothing else is ever sent unprompted.") {
                    ZenithToggle(isOn: $store.settings.doneText)
                }
                row("Never without a thumbs up", "Spending money and posting publicly always wait for you. This can't be turned off.") {
                    Image(systemName: "lock").foregroundStyle(Theme.ink3)
                }
            }

            section("Galaxy Link") {
                row(connector.connected ? "Connected as zenith" : "Not running",
                    connector.connected ? "Handoffs, approvals, status and the done text go through Link." : "Zenith works alone until Link starts: no Nova, Comet or Nebula, and no missions from them.") {
                    HStack(spacing: 6) {
                        ForEach(connector.bodies.filter { $0.id != "zenith" }) { b in
                            Pill(text: b.name, color: b.online ? Theme.good : Theme.ink3)
                        }
                    }
                }
            }

            section("This Mac") {
                row("Launch at login", "Start Zenith in the menu bar, so missions and living missions keep going.") {
                    ZenithToggle(isOn: Binding(get: { launchAtLogin }, set: { on in
                        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }))
                }
                row("Your data", "Missions, workspaces and snapshots, all on this Mac.") {
                    Button("Show in Finder") { NSWorkspace.shared.open(store.dir) }.buttonStyle(ZenithButtonStyle())
                }
            }
        }
        .task {
            let path = store.settings.claudePath
            claudeFound = await Task.detached { ClaudeCode.locate(path) }.value
        }
    }

    private var claudeLine: String {
        if let claudeFound { return "Using \(claudeFound), logged into your Max plan. Zenith clears any API key from its environment so the plan is always what's used." }
        return "Not found. Install Claude Code and log in with your Max plan, or set its path."
    }

    private var cloudLine: String {
        switch commander.cloudCheck {
        case .checking: return "Starting a cloud session and waiting for its answer. This can take a few minutes."
        case .failed(let why): return "Didn't pass: \(why) Missions run in the sandbox on this Mac."
        case .passed: return "Passed. Missions run in Claude Code cloud sessions."
        case .idle:
            if let at = store.settings.cloudVerifiedAt { return "Passed \(Format.date(at)). Missions run in Claude Code cloud sessions." }
            return "Starts a tiny cloud session from this Mac and reads its answer back. Until it passes, missions run in the sandbox."
        }
    }

    private func addContact() {
        let c = newContact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty, !store.settings.allowlist.contains(c) else { return }
        store.settings.allowlist.append(c)
        newContact = ""
    }

    private func hourPicker(_ hour: Binding<Int>) -> some View {
        Picker("", selection: hour) {
            ForEach(0..<24, id: \.self) { h in Text(String(format: "%02d:00", h)).tag(h) }
        }
        .labelsHidden()
        .frame(width: 90)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(title).padding(.bottom, 12)
            VStack(alignment: .leading, spacing: 16) { content() }
                .padding(20)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        }
    }

    private func row<Control: View>(_ title: String, _ detail: String, @ViewBuilder _ control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(detail).font(Theme.body(12)).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            control()
        }
    }
}
