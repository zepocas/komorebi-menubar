import AppKit
import MenubarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let paths = Paths.resolve()
    lazy var services = ServiceController(paths: paths)
    lazy var profiles = ProfileStore(paths: paths)
    let watcher = ServiceWatcher()
    let menu = NSMenu()

    /// Actions currently running, e.g. "komorebi", used to show progress in the menu.
    var busy: Set<String> = []

    private var statusItem: StatusItemController!
    private var subscriber: KomorebiSubscriber?
    private var lastLabel: WorkspaceLabel?
    private var connectTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only one menubar item: the newest copy wins and asks older ones to quit. `brew upgrade`
        // both reopens the app and kickstarts its login agent, and deferring to the older copy
        // would lose both while the old one is still quitting. A clean quit exits 0, so the login
        // agent's KeepAlive leaves it be.
        let me = NSRunningApplication.current.processIdentifier
        for other in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        where other.processIdentifier != me {
            other.terminate()
        }

        menu.delegate = self
        menu.autoenablesItems = false
        statusItem = StatusItemController(menu: menu)

        do {
            try profiles.ensureActiveLink()
        } catch {
            presentError("Couldn't create \(paths.activeProfileLink.path)", error)
        }

        let subscriber = KomorebiSubscriber(dataDir: paths.dataDir) { [weak self] state in
            Task { @MainActor in self?.render(state) }
        }
        do {
            try subscriber.start()
            self.subscriber = subscriber
        } catch {
            presentError("Couldn't listen for komorebi events", error)
        }

        watcher.onKomorebiStarted = { [weak self] in self?.connect() }
        watcher.onKomorebiStopped = { [weak self] in self?.disconnected() }
        watcher.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        subscriber?.stop()
    }

    // MARK: komorebi connection

    /// Subscribes (retrying while komorebi finishes booting and opens komorebi.sock) and renders
    /// the current state right away instead of waiting for the next event.
    func connect() {
        connectTask?.cancel()
        connectTask = Task {
            for _ in 0..<25 {
                if Task.isCancelled { return }
                if (try? await services.subscribe()) != nil {
                    if let state = try? await services.fetchState() {
                        render(state)
                    }
                    return
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    private func disconnected() {
        connectTask?.cancel()
        lastLabel = nil
        statusItem.showDisconnected()
    }

    private func render(_ state: KomorebiState) {
        guard watcher.komorebiPID != nil else { return }
        let label = WorkspaceLabel(state: state)
        // komorebi emits a steady stream of events (window moves, focus changes...). Only redraw
        // when the text actually changes.
        guard label != lastLabel else { return }
        lastLabel = label
        statusItem.show(label)
    }

    // MARK: actions

    /// Points `active.json` at `profile` and restarts komorebi so it boots with it.
    /// (`komorebic replace-configuration` would be the live alternative, but it panics komorebi
    /// in the current komorebi-for-mac build.)
    func activateProfile(_ profile: URL) {
        run("profile", failure: "Couldn't switch profile") { [services, profiles] in
            let running = ProcessLookup.pid(named: "komorebi") != nil
            if running {
                // Fail before touching the link if komorebi can't be restarted to pick it up.
                try services.agents.prepare(.komorebi)
            }
            try profiles.activate(profile)
            if running {
                try await services.restartKomorebi()
            }
        }
    }

    func restartKomorebi() {
        run("komorebi", failure: "Couldn't start komorebi") { [services] in try await services.restartKomorebi() }
    }

    func restartSkhd() {
        run("skhd", failure: "Couldn't start skhd") { [services] in try await services.restartSkhd() }
    }

    func toggleStartsAtLogin(_ agent: LaunchAgents.Agent) {
        let agents = services.agents
        let on = !agents.startsAtLogin(agent)
        run("login", failure: "Couldn't change Start at Login") {
            try await agents.setStartsAtLogin(agent, on)
        }
    }

    private func run(_ name: String, failure: String, _ action: @escaping @Sendable () async throws -> Void) {
        guard !busy.contains(name) else { return }
        busy.insert(name)
        Task {
            defer {
                busy.remove(name)
                watcher.poll()
            }
            do {
                try await action()
            } catch {
                presentError(failure, error)
            }
        }
    }

    func presentError(_ title: String, _ error: any Error) {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
