import AppKit
import MenubarCore

/// The menu is rebuilt each time it opens so the status and profile list are always current.
extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        watcher.poll()
        menu.removeAllItems()

        menu.addItem(serviceStatusItem(name: "komorebi", pid: watcher.komorebiPID))
        menu.addItem(serviceStatusItem(name: "skhd", pid: watcher.skhdPID))
        menu.addItem(.separator())

        let profilesItem = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
        profilesItem.submenu = profilesMenu()
        menu.addItem(profilesItem)
        menu.addItem(.separator())

        menu.addItem(serviceItem(name: "komorebi", running: watcher.komorebiPID != nil) { [weak self] in self?.restartKomorebi() })
        menu.addItem(serviceItem(name: "skhd", running: watcher.skhdPID != nil) { [weak self] in self?.restartSkhd() })
        menu.addItem(.separator())

        menu.addItem(ActionMenuItem(title: "Open Config Folder") { [paths] in
            NSWorkspace.shared.open(paths.configDir)
        })
        menu.addItem(ActionMenuItem(title: "Quit Komorebi Menubar", keyEquivalent: "q") {
            NSApp.terminate(nil)
        })
    }

    private func serviceStatusItem(name: String, pid: pid_t?) -> NSMenuItem {
        let item = NSMenuItem(title: pid.map { "\(name) — running (pid \($0))" } ?? "\(name) — not running", action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 8, weight: .regular).applying(.init(paletteColors: [pid == nil ? .systemRed : .systemGreen])))
        return item
    }

    private func serviceItem(name: String, running: Bool, action: @escaping () -> Void) -> NSMenuItem {
        if busy.contains(name) {
            let item = NSMenuItem(title: "\(running ? "Restarting" : "Starting") \(name)…", action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        }
        return ActionMenuItem(title: "\(running ? "Restart" : "Start") \(name)", handler: action)
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
            item.isEnabled = !busy.contains("profile")
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
