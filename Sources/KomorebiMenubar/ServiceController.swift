import Foundation
import MenubarCore

struct ServiceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Talks to komorebi (through `komorebic`) and starts/restarts komorebi and skhd through launchd.
///
/// Starts only go through our LaunchAgents (see LaunchAgents), installed on demand. If this app
/// spawned the daemons itself, macOS would treat the app as their "responsible process" and check
/// *its* Accessibility and Screen Recording grants instead of komorebi's/skhd's own (komorebi then
/// dies with "failed to request screen capability"). As launchd jobs they are responsible for
/// themselves.
struct ServiceController: Sendable {
    let paths: Paths
    var agents: LaunchAgents { LaunchAgents(paths: paths) }

    // MARK: komorebi

    func subscribe() async throws {
        try await komorebic(["subscribe-socket", KomorebiSubscriber.socketName])
    }

    func fetchState() async throws -> KomorebiState {
        let result = try await komorebic(["state"])
        return try KomorebiDecoder.state(fromStateJSON: result.stdout)
    }

    func restartKomorebi() async throws {
        // Before stopping anything, so a missing komorebi binary doesn't leave komorebi down.
        try agents.prepare(.komorebi)

        if let pid = ProcessLookup.pid(named: "komorebi") {
            // `stop` restores hidden windows before exiting, which a plain kill wouldn't. komorebi can
            // wedge after an internal panic and ignore commands, so fall back to SIGTERM.
            let stopped = await Shell.run(paths.komorebic, ["stop"], environment: paths.childEnvironment).succeeded
            let exited = stopped ? await wait(timeout: .seconds(5)) { ProcessLookup.pid(named: "komorebi") == nil } : false
            if !exited {
                kill(pid, SIGTERM)
                try await waitFor("komorebi to exit", timeout: .seconds(5)) { ProcessLookup.pid(named: "komorebi") == nil }
            }
        }
        // Loading an agent that starts at login already starts komorebi; kickstart covers the rest.
        try await agents.load(.komorebi)
        try await kickstart(.komorebi, killingRunning: false)
        try await waitFor("komorebi to start (see ~/Library/Logs/komorebi.log)", timeout: .seconds(10)) {
            ProcessLookup.pid(named: "komorebi") != nil
        }
    }

    // MARK: skhd

    func restartSkhd() async throws {
        try await agents.requireNoForeignSkhd()
        try agents.prepare(.skhd)
        if await !agents.isLoaded(.skhd), let pid = ProcessLookup.pid(named: "skhd") {
            // Started by hand: stop it so launchd's copy doesn't run next to it.
            kill(pid, SIGTERM)
            try await waitFor("skhd to exit", timeout: .seconds(5)) { ProcessLookup.pid(named: "skhd") == nil }
        }
        try await agents.load(.skhd)
        try await kickstart(.skhd, killingRunning: true)

        try await waitFor("skhd to start (see ~/Library/Logs/skhd.log)", timeout: .seconds(5)) {
            ProcessLookup.pid(named: "skhd") != nil
        }
        // skhd aborts right after launch when it lacks Accessibility access, so make sure it stays up.
        try await Task.sleep(for: .seconds(1))
        guard ProcessLookup.pid(named: "skhd") != nil else {
            throw ServiceError(message: "skhd exited right after starting. Grant skhd Accessibility access in System Settings → Privacy & Security → Accessibility.")
        }
    }

    // MARK: helpers

    @discardableResult
    private func komorebic(_ arguments: [String]) async throws -> ShellResult {
        let result = await Shell.run(paths.komorebic, arguments, environment: paths.childEnvironment)
        guard result.succeeded else {
            let detail = result.stderr.isEmpty ? "exit code \(result.status)" : result.stderr
            throw ServiceError(message: "komorebic \(arguments.joined(separator: " ")) failed: \(detail)")
        }
        return result
    }

    private func kickstart(_ agent: LaunchAgents.Agent, killingRunning: Bool) async throws {
        let target = "gui/\(getuid())/\(agent.label)"
        let result = await Shell.run(paths.launchctl, ["kickstart"] + (killingRunning ? ["-k"] : []) + [target], environment: paths.childEnvironment)
        guard result.succeeded else {
            throw ServiceError(message: "launchctl kickstart \(agent.label) failed: \(result.stderr)")
        }
    }

    private func waitFor(_ what: String, timeout: Duration, _ condition: () -> Bool) async throws {
        guard await wait(timeout: timeout, until: condition) else {
            throw ServiceError(message: "Timed out waiting for \(what).")
        }
    }

    /// Polls `condition` until it holds or `timeout` passes; returns whether it held.
    private func wait(timeout: Duration, until condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return true
    }
}
