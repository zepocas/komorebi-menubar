import AppKit
import MenubarCore

/// The menu is rebuilt each time it opens so the status and profile list are always current.
extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        watcher.poll()
        menu.removeAllItems()

        let profilesItem = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
        profilesItem.submenu = profilesMenu()
        menu.addItem(profilesItem)
        menu.addItem(.separator())

        menu.addItem(serviceMenu(name: "komorebi", pid: watcher.komorebiPID,
                                 start: { [weak self] in self?.startKomorebi() },
                                 restart: { [weak self] in self?.restartKomorebi() },
                                 stop: { [weak self] in self?.stopKomorebi() }))
        menu.addItem(serviceMenu(name: "skhd", pid: watcher.skhdPID,
                                 start: { [weak self] in self?.startSkhd() },
                                 restart: { [weak self] in self?.restartSkhd() },
                                 stop: { [weak self] in self?.stopSkhd() }))
        menu.addItem(.separator())

        let startup = NSMenuItem(title: "Start at Login", action: nil, keyEquivalent: "")
        startup.submenu = startupMenu()
        menu.addItem(startup)
        menu.addItem(ActionMenuItem(title: "Open Config Folder") { [paths] in
            NSWorkspace.shared.open(paths.configDir)
        })
        menu.addItem(ActionMenuItem(title: "Quit Komorebi Menubar", keyEquivalent: "q") {
            NSApp.terminate(nil)
        })
    }

    /// "● name — status ▸ Stop / Start, Restart".
    private func serviceMenu(name: String, pid: pid_t?, start: @escaping () -> Void, restart: @escaping () -> Void, stop: @escaping () -> Void) -> NSMenuItem {
        let state = ServiceMenuState(pid: pid, activity: busy[name])
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        let toggle = ActionMenuItem(title: state.toggleTitle, handler: state.toggleStops ? stop : start)
        toggle.isEnabled = state.isToggleEnabled
        submenu.addItem(toggle)

        let restartItem = ActionMenuItem(title: "Restart", handler: restart)
        restartItem.isEnabled = state.isRestartEnabled
        submenu.addItem(restartItem)

        let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
        let title = NSMutableAttributedString(string: name)
        title.append(NSAttributedString(string: " — \(state.status)", attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
        item.attributedTitle = title
        item.image = Self.statusDot(running: state.isRunning)
        item.submenu = submenu
        return item
    }

    /// Drawn by hand rather than via an SF Symbol: symbol images are templates, which menus
    /// can render monochrome, dropping the green/red tint.
    private static func statusDot(running: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            (running ? NSColor.systemGreen : NSColor.systemRed).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    private func startupMenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let agents = services.agents
        let items: [(String, LaunchAgents.Agent, URL?)] = [
            ("Komorebi Menubar", .menubar, Bundle.main.executableURL),
            ("komorebi", .komorebi, paths.komorebi),
            ("skhd", .skhd, paths.skhd),
        ]
        for (title, agent, binary) in items {
            let item = ActionMenuItem(title: title) { [weak self] in self?.toggleStartsAtLogin(agent) }
            item.state = agents.startsAtLogin(agent) ? .on : .off
            item.isEnabled = binary != nil && busy["login"] == nil
            if binary == nil {
                item.toolTip = "\(title) isn't installed in ~/.local/bin, /opt/homebrew/bin or /usr/local/bin."
            }
            submenu.addItem(item)
        }
        return submenu
    }

    private func profilesMenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let active = profiles.activeProfileName()
        let available = profiles.available()

        if available.isEmpty {
            let empty = NSMenuItem(title: "No komorebi*.json in \(paths.configDir.path)", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        }
        for profile in available {
            let fileName = profile.lastPathComponent
            let item = ActionMenuItem(title: ProfileDiscovery.displayName(forProfile: fileName)) { [weak self] in
                self?.activateProfile(profile)
            }
            item.toolTip = fileName
            item.state = fileName == active ? .on : .off
            item.isEnabled = busy["profile"] == nil
            submenu.addItem(item)
        }
        return submenu
    }
}

/// NSMenuItem that runs a closure, avoiding a selector per action.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, keyEquivalent: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func fire() {
        handler()
    }
}
