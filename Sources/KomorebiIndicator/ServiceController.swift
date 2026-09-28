import Foundation
import IndicatorCore

struct ServiceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Talks to komorebi (through `komorebic`) and restarts komorebi/skhd through launchd.
///
/// Restarts only go through the LaunchAgents in `launchd/`. If this app spawned the daemons itself,
/// macOS would treat the app as their "responsible process" and check *its* Accessibility and
/// Screen Recording grants instead of komorebi's/skhd's own (komorebi then dies with
/// "failed to request screen capability"). As launchd jobs they are responsible for themselves.
struct ServiceController: Sendable {
    static let komorebiAgent = "com.zepocas.komorebi"
    static let skhdAgent = "com.zepocas.skhd"

    let paths: Paths

    // MARK: komorebi

    func subscribe() async throws {
        try await komorebic(["subscribe-socket", KomorebiSubscriber.socketName])
    }

    func fetchState() async throws -> KomorebiState {
        let result = try await komorebic(["state"])
        return try KomorebiDecoder.state(fromStateJSON: result.stdout)
    }

    func restartKomorebi() async throws {
        // Check before stopping anything, so a missing agent doesn't leave komorebi down.
        try await requireAgent(Self.komorebiAgent)

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
        try await kickstart(Self.komorebiAgent)
        try await waitFor("komorebi to start (see ~/Library/Logs/komorebi.log)", timeout: .seconds(10)) {
            ProcessLookup.pid(named: "komorebi") != nil
        }
    }

    // MARK: skhd

    func restartSkhd() async throws {
        try await requireAgent(Self.skhdAgent)
        try await kickstart(Self.skhdAgent)

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

    func requireAgent(_ label: String) async throws {
        let loaded = await Shell.run(paths.launchctl, ["print", "gui/\(getuid())/\(label)"], environment: paths.childEnvironment).succeeded
        guard loaded else {
            throw ServiceError(message: "The \(label) LaunchAgent isn't loaded. Run `make agents` in the komorebi-indicator repo so launchd can manage it.")
        }
    }

    private func kickstart(_ label: String) async throws {
        let result = await Shell.run(paths.launchctl, ["kickstart", "-k", "gui/\(getuid())/\(label)"], environment: paths.childEnvironment)
        guard result.succeeded else {
            throw ServiceError(message: "launchctl kickstart \(label) failed: \(result.stderr)")
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
