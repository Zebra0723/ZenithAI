import AppKit
import Combine
import SwiftUI
import ZenithCore

@main
enum ZenithMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // menu bar only until the window opens
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let window = AppWindowController()
    private var watch: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()
        watch = Store.shared.$missions
            .map { missions in missions.contains { $0.isActive } }
            .removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateIcon() } }

        Commander.shared.start()
        Connector.shared.start()
        if Self.firstRun { window.show(.new) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Commander.shared.shutdown()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            await GalaxyLink.shared.goodbye()
            done.signal()
        }
        _ = done.wait(timeout: .now() + 1)
    }

    // MARK: - Menu bar

    private func updateIcon() {
        let working = Store.shared.missions.contains { $0.isActive }
        statusItem.button?.image = Self.icon(working: working)
        statusItem.button?.toolTip = working ? "Zenith is working on a mission" : "Zenith"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let missions = Store.shared.missions
        let active = missions.filter { !$0.isFinished && $0.status != .stopped }
        let header = NSMenuItem(title: active.isEmpty ? "No missions running" : "\(active.count) \(active.count == 1 ? "mission" : "missions")",
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for m in active.prefix(6) {
            let item = NSMenuItem(title: "\(m.title): \(Prompts.phrase(m.status))", action: #selector(openMission(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = m.id
            menu.addItem(item)
        }
        let waiting = missions.filter { $0.status == .needsYou }.reduce(0) { $0 + $1.openQuestions.count }
        if waiting > 0 {
            menu.addItem(.separator())
            menu.addItem(item("\(waiting) \(waiting == 1 ? "Question Waits" : "Questions Wait") for You", #selector(openNeedsYou)))
        }
        if let r = Commander.shared.reading {
            menu.addItem(.separator())
            let budget = NSMenuItem(title: "\(Format.percent(r.usedPercent)) of the week used, cap \(Int(r.capPercent))%", action: nil, keyEquivalent: "")
            budget.isEnabled = false
            menu.addItem(budget)
        }
        menu.addItem(.separator())
        menu.addItem(item("New Mission…", #selector(openNew)))
        menu.addItem(item("Open Zenith", #selector(openBoard)))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Zenith", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    @objc private func openMission(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        window.show(mission: id)
    }

    @objc private func openNeedsYou() { window.show(.needsYou) }
    @objc private func openNew() { window.show(.new) }
    @objc private func openBoard() {
        window.navigation.missionID = nil
        window.show(.board)
    }
    @objc private func openSettings() { window.show(.settings) }

    /// The mark as a template image: the horizon, the line rising from it, and the sun,
    /// filled while a mission is working.
    private static func icon(working: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let s = rect.width
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setLineCap(.round)
            ctx.setLineWidth(1.5)
            ctx.move(to: CGPoint(x: s * 0.10, y: s * 0.84))
            ctx.addQuadCurve(to: CGPoint(x: s * 0.90, y: s * 0.84), control: CGPoint(x: s * 0.5, y: s * 0.68))
            ctx.strokePath()
            ctx.setLineWidth(1.2)
            ctx.move(to: CGPoint(x: s * 0.5, y: s * 0.74))
            ctx.addLine(to: CGPoint(x: s * 0.5, y: s * 0.40))
            ctx.strokePath()
            let d = s * 0.30
            let sun = CGRect(x: s * 0.5 - d / 2, y: s * 0.07, width: d, height: d)
            if working {
                ctx.fillEllipse(in: sun)
            } else {
                ctx.setLineWidth(1.3)
                ctx.strokeEllipse(in: sun.insetBy(dx: 0.65, dy: 0.65))
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = working ? "Zenith, working" : "Zenith"
        return image
    }

    // MARK: - Main menu (while the window is open)

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Zenith", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settingsItem = item("Settings…", #selector(openSettings))
        settingsItem.keyEquivalent = ","
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Zenith", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Zenith", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        let file = NSMenu(title: "File")
        let newItem = item("New Mission", #selector(openNew))
        newItem.keyEquivalent = "n"
        file.addItem(newItem)
        let fileItem = NSMenuItem()
        fileItem.submenu = file
        main.addItem(fileItem)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        main.addItem(editItem)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu
        return main
    }

    static var firstRun: Bool {
        let key = "ZenithLaunched"
        defer { UserDefaults.standard.set(true, forKey: key) }
        return !UserDefaults.standard.bool(forKey: key)
    }
}
