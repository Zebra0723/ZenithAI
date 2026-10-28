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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Zenith"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = NSColor(Theme.ground)
        window.minSize = NSSize(width: 1040, height: 660)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: RootView(navigation: navigation)
            .environment(\.colorScheme, .light))
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
        HStack(spacing: 0) {
            sidebar
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
            .background(Theme.ground)
        }
        .ignoresSafeArea()
        .foregroundStyle(Theme.ink)
        .tint(Theme.ink)
    }

    private var openQuestions: Int {
        store.missions.filter { $0.status == .needsYou || $0.status == .living }.reduce(0) { $0 + $1.openQuestions.count }
    }

    private var working: Bool { store.missions.contains { $0.isActive } }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                ZenithGlyph(live: working, onNight: true).frame(width: 20, height: 20)
                Text("Zenith").font(Theme.display(18)).foregroundStyle(Theme.nightInk)
            }
            .padding(.horizontal, 12)
            .padding(.top, 54)
            .padding(.bottom, 28)

            ForEach(AppSection.allCases) { section in
                SidebarRow(section: section, selected: navigation.section == section,
                           badge: section == .needsYou ? openQuestions : 0) {
                    navigation.section = section
                    if section == .board { navigation.missionID = nil }
                }
                if section == .new || section == .living {
                    Rectangle().fill(Theme.nightLine).frame(height: 1).padding(.vertical, 10).padding(.horizontal, 12)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 14) {
                if let r = commander.reading {
                    Button { navigation.section = .budget } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("This week").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.nightInk2)
                                Spacer()
                                Text("\(Format.percent(r.usedPercent)) of \(Int(r.capPercent))%")
                                    .font(Theme.mono(10.5)).foregroundStyle(Theme.nightInk)
                            }
                            NightMeter(value: r.usedPercent / 100, cap: r.capPercent / 100)
                        }
                        .padding(12)
                        .background(Theme.nightRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                HStack(spacing: 7) {
                    Circle().fill(connector.connected ? Theme.sun : Theme.nightLine).frame(width: 6, height: 6)
                    Text(connector.connected ? "Galaxy Link connected" : "Galaxy Link not running")
                        .font(.system(size: 11)).foregroundStyle(Theme.nightInk2)
                }
                .padding(.horizontal, 4)
            }
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 12)
        .frame(width: 228)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.night)
        .environment(\.colorScheme, .dark)
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
            HStack(spacing: 11) {
                Image(systemName: section.icon)
                    .font(.system(size: 12.5))
                    .frame(width: 18)
                    .foregroundStyle(selected ? Theme.sun : Theme.nightInk2)
                Text(section.title)
                    .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.nightInk : Theme.nightInk2)
                Spacer()
                if badge > 0 {
                    Text("\(badge)")
                        .font(Theme.mono(10.5, weight: .semibold))
                        .foregroundStyle(Theme.night)
                        .padding(.horizontal, 6)
                        .frame(height: 17)
                        .background(Theme.sun, in: Capsule())
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 33)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Theme.nightRaised : (hovering ? Theme.nightRaised.opacity(0.5) : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// The weekly meter on the night sidebar, with the cap marked.
struct NightMeter: View {
    var value: Double
    var cap: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.nightLine)
                Capsule().fill(value >= cap ? Theme.alert : Theme.sun)
                    .frame(width: max(3, min(1, value) * geo.size.width))
                Rectangle().fill(Theme.nightInk).frame(width: 1.5, height: 10)
                    .offset(x: cap * geo.size.width - 0.75)
            }
        }
        .frame(height: 5)
    }
}
