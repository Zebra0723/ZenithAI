import AppKit
import SwiftUI
import ZenithCore

enum AppSection: String, CaseIterable, Identifiable {
    case board, new, needsYou, replay, living, budget, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .board: return "Mission board"
        case .new: return "New mission"
        case .needsYou: return "Needs you"
        case .replay: return "Replay"
        case .living: return "Living"
        case .budget: return "Galaxy budget"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .board: return "square.grid.3x2"
        case .new: return "plus"
        case .needsYou: return "questionmark.bubble"
        case .replay: return "clock.arrow.circlepath"
        case .living: return "arrow.triangle.2.circlepath"
        case .budget: return "gauge.with.dots.needle.33percent"
        case .settings: return "slider.horizontal.3"
        }
    }
}

@MainActor
final class Navigation: ObservableObject {
    @Published var section: AppSection = .board
    /// The mission open on the board, if any.
    @Published var missionID: String?
    /// The mission open in Replay.
    @Published var replayID: String?

    func open(_ id: String) {
        section = .board
        missionID = id
    }
}

/// The Zenith window.
@MainActor
final class AppWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    let navigation = Navigation()

    func show(_ section: AppSection? = nil, mission: String? = nil) {
        if let section { navigation.section = section }
        if let mission { navigation.open(mission) }
        if window == nil { window = makeWindow() }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1300, height: 840),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Zenith"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 0.03, green: 0.04, blue: 0.09, alpha: 1)
        window.minSize = NSSize(width: 1080, height: 700)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: RootView(navigation: navigation)
            .environment(\.colorScheme, .dark))
        window.center()
        window.setFrameAutosaveName("ZenithWindow")
        return window
    }
}

struct RootView: View {
    @ObservedObject var navigation: Navigation
    @ObservedObject private var store = Store.shared
    @ObservedObject private var commander = Commander.shared
    @ObservedObject private var connector = Connector.shared

    var body: some View {
        ZStack {
            SkyBackground()
            HStack(spacing: 0) {
                sidebar
                    .padding(.leading, 12)
                    .padding(.vertical, 12)
                Group {
                    switch navigation.section {
                    case .board:
                        if let id = navigation.missionID, store.mission(id) != nil {
                            MissionView(id: id, navigation: navigation)
                        } else {
                            BoardView(navigation: navigation)
                        }
                    case .new: NewMissionView(navigation: navigation)
                    case .needsYou: NeedsYouView(navigation: navigation)
                    case .replay: ReplayView(navigation: navigation)
                    case .living: LivingView(navigation: navigation)
                    case .budget: BudgetView()
                    case .settings: SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.18), value: navigation.section)
            }
        }
        .ignoresSafeArea()
        .foregroundStyle(Theme.ink)
        .tint(Theme.sun)
    }

    private var openQuestions: Int {
        store.missions.filter { $0.status == .needsYou || $0.status == .living }.reduce(0) { $0 + $1.openQuestions.count }
    }

    private var working: Bool { store.missions.contains { $0.isActive } }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 11) {
                ZenithGlyph(live: working).frame(width: 22, height: 22)
                Text("Zenith").font(Theme.display(23, weight: .regular)).tracking(-0.3)
            }
            .padding(.horizontal, 12)
            .padding(.top, 46)
            .padding(.bottom, 30)

            ForEach(AppSection.allCases) { section in
                SidebarRow(section: section, selected: navigation.section == section,
                           badge: section == .needsYou ? openQuestions : 0) {
                    navigation.section = section
                    if section == .board { navigation.missionID = nil }
                }
                if section == .new || section == .living {
                    Rule().padding(.vertical, 12).padding(.horizontal, 12)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                if let r = commander.reading {
                    Button { navigation.section = .budget } label: {
                        HStack(spacing: 14) {
                            SunDial(value: r.usedPercent / 100, cap: r.capPercent / 100, lineWidth: 4, label: "", caption: "")
                                .frame(width: 38, height: 38)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(Format.percent(r.usedPercent)).font(Theme.numeral(20, weight: .light))
                                Text("of the week · cap \(Int(r.capPercent))%").font(.system(size: 10.5)).foregroundStyle(Theme.ink3)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                HStack(spacing: 8) {
                    Circle().fill(connector.connected ? Theme.good : Theme.ink4).frame(width: 6, height: 6)
                        .shadow(color: connector.connected ? Theme.good : .clear, radius: 3)
                    Text(connector.connected ? "Galaxy Link connected" : "Galaxy Link not running")
                        .font(.system(size: 11)).foregroundStyle(Theme.ink3)
                }
                .padding(.horizontal, 6)
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 10)
        .frame(width: 232)
        .frame(maxHeight: .infinity, alignment: .top)
        .glass(radius: 22)
    }
}

private struct SidebarRow: View {
    let section: AppSection
    let selected: Bool
    var badge: Int = 0
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: section.icon)
                    .font(.system(size: 12.5, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(selected ? Theme.sun : Theme.ink3)
                Text(section.title)
                    .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.ink : Theme.ink2)
                Spacer()
                if badge > 0 {
                    Text("\(badge)")
                        .font(Theme.mono(10.5, weight: .bold))
                        .foregroundStyle(Color(red: 0.1, green: 0.07, blue: 0.03))
                        .padding(.horizontal, 7)
                        .frame(height: 18)
                        .background(Theme.sun, in: Capsule())
                        .shadow(color: Theme.sunGlow, radius: 6)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 35)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.glassStrong)
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                } else if hovering {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.glass)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
