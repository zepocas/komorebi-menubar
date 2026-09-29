import Foundation
import MenubarCore

/// The LaunchAgents this app manages in ~/Library/LaunchAgents: the app itself, komorebi and skhd.
///
/// Start at Login only rewrites the plist (or, for the app itself, deletes it); launchd reads it at
/// the next login. It never boots out a loaded job: the app's own job may be running this very
/// process, and komorebi and skhd should keep running for the rest of the session.
struct LaunchAgents: Sendable {
    enum Agent: Sendable {
        case menubar, komorebi, skhd

        var label: String {
            switch self {
            case .menubar: "io.github.zepocas.komorebi-menubar"
            case .komorebi: "io.github.zepocas.komorebi"
            case .skhd: "io.github.zepocas.skhd"
            }
        }

        var kind: LaunchAgentPlist.Kind {
            switch self {
            case .menubar: .menubar
            case .komorebi: .komorebi
            case .skhd: .skhd
            }
        }

        var logName: String {
            switch self {
            case .menubar: "komorebi-menubar.log"
            case .komorebi: "komorebi.log"
            case .skhd: "skhd.log"
            }
        }
    }

    /// Jobs other tools install that also run skhd. Ours running next to one would start it twice.
    private static let foreignSkhdLabels = ["com.koekeishiya.skhd", "homebrew.mxcl.skhd"]

    let paths: Paths

    func plistURL(_ agent: Agent) -> URL {
        paths.home.appendingPathComponent("Library/LaunchAgents/\(agent.label).plist")
    }

    func startsAtLogin(_ agent: Agent) -> Bool {
        guard let plist = NSDictionary(contentsOf: plistURL(agent)) as? [String: Any] else { return false }
        return LaunchAgentPlist.startsAtLogin(plist)
    }

    func setStartsAtLogin(_ agent: Agent, _ on: Bool) async throws {
        if agent == .skhd, on {
            try await requireNoForeignSkhd()
        }
        if agent == .menubar, !on {
            try FileManager.default.removeItem(at: plistURL(agent))
        } else {
            try write(agent, startsAtLogin: on)
        }
    }

    /// Installs the plist, not starting at login, if it's missing, so the menu can start the daemon
    /// through launchd without any setup. Throws if the daemon can't be found.
    func prepare(_ agent: Agent) throws {
        guard !FileManager.default.fileExists(atPath: plistURL(agent).path) else { return }
        try write(agent, startsAtLogin: false)
    }

    func isLoaded(_ agent: Agent) async -> Bool {
        await isLoaded(label: agent.label)
    }

    func load(_ agent: Agent) async throws {
        guard await !isLoaded(agent) else { return }
        let result = await Shell.run(paths.launchctl, ["bootstrap", "gui/\(getuid())", plistURL(agent).path], environment: paths.childEnvironment)
        guard result.succeeded else {
            throw ServiceError(message: "launchctl bootstrap \(agent.label) failed: \(result.stderr)")
        }
    }

    func requireNoForeignSkhd() async throws {
        for label in Self.foreignSkhdLabels where await isLoaded(label: label) {
            throw ServiceError(message: "skhd is also started by the \(label) LaunchAgent, so it would run twice. Remove that one first: `skhd --uninstall-service` or `brew services stop skhd`.")
        }
    }

    private func isLoaded(label: String) async -> Bool {
        await Shell.run(paths.launchctl, ["print", "gui/\(getuid())/\(label)"], environment: paths.childEnvironment).succeeded
    }

    private func write(_ agent: Agent, startsAtLogin: Bool) throws {
        var environment = ["KOMOREBI_CONFIG_HOME": paths.configDir.path]
        if agent != .menubar {
            // skhd runs its bindings through a shell; both need the PATH that has komorebic.
            environment["PATH"] = paths.agentPath
        }
        let plist = LaunchAgentPlist.make(
            kind: agent.kind,
            label: agent.label,
            programArguments: try programArguments(agent),
            environment: environment,
            log: paths.home.appendingPathComponent("Library/Logs/\(agent.logName)").path,
            startsAtLogin: startsAtLogin
        )
        let url = plistURL(agent)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url, options: .atomic)
    }

    private func programArguments(_ agent: Agent) throws -> [String] {
        switch agent {
        case .menubar:
            return [Bundle.main.executablePath!]
        case .komorebi:
            guard let komorebi = paths.komorebi else {
                throw ServiceError(message: "Couldn't find komorebi in ~/.local/bin, /opt/homebrew/bin, /usr/local/bin or your PATH.")
            }
            // The daemon itself, not `komorebic start`, which forks it away from launchd and mangles
            // --config. active.json is the profile symlink this app manages.
            return [komorebi.path, "--config", paths.activeProfileLink.path]
        case .skhd:
            guard let skhd = paths.skhd else {
                throw ServiceError(message: "Couldn't find skhd in ~/.local/bin, /opt/homebrew/bin, /usr/local/bin or your PATH.")
            }
            return [skhd.path, "-c", paths.skhdConfig.path]
        }
    }
}
