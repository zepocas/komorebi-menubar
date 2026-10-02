import Foundation
import MenubarCore

/// Absolute locations of binaries and config. GUI apps (and launchd jobs) don't get the shell's
/// PATH, so `~/.local/bin` etc. are searched explicitly instead of relying on the environment.
struct Paths: Sendable {
    let home: URL
    let configDir: URL
    let dataDir: URL
    let komorebic: URL
    let komorebi: URL?
    let skhd: URL?
    /// `<config dir>/skhdrc` if it exists, otherwise `~/.config/skhd/skhdrc`.
    let skhdConfig: URL
    let launchctl = URL(fileURLWithPath: "/bin/launchctl")
    /// PATH written into the launchd agents. Fixed rather than inherited, so it doesn't depend on how
    /// the app happened to be launched (a terminal's PATH would otherwise end up in the agents).
    let agentPath: String
    /// Environment handed to every child process.
    let childEnvironment: [String: String]

    var activeProfileLink: URL { configDir.appendingPathComponent(ProfileDiscovery.activeLinkName) }

    static func resolve() -> Paths {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let environment = ProcessInfo.processInfo.environment

        let configDir = environment["KOMOREBI_CONFIG_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? home.appendingPathComponent(".config/komorebi", isDirectory: true)

        let preferredDirs = [home.appendingPathComponent(".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin"]
        let systemDirs = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let searchDirs = preferredDirs + (environment["PATH"]?.split(separator: ":").map(String.init) ?? []) + systemDirs
        func find(_ name: String) -> URL? {
            searchDirs
                .map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
                .first { fileManager.isExecutableFile(atPath: $0.path) }
        }

        var childEnvironment = environment
        childEnvironment["PATH"] = Array(NSOrderedSet(array: searchDirs)).compactMap { $0 as? String }.joined(separator: ":")
        childEnvironment["KOMOREBI_CONFIG_HOME"] = configDir.path

        let skhdConfig = configDir.appendingPathComponent("skhdrc")

        return Paths(
            home: home,
            configDir: configDir,
            dataDir: home.appendingPathComponent("Library/Application Support/komorebi", isDirectory: true),
            komorebic: find("komorebic") ?? home.appendingPathComponent(".local/bin/komorebic"),
            komorebi: find("komorebi"),
            skhd: find("skhd"),
            skhdConfig: fileManager.fileExists(atPath: skhdConfig.path) ? skhdConfig : home.appendingPathComponent(".config/skhd/skhdrc"),
            agentPath: (preferredDirs + systemDirs).joined(separator: ":"),
            childEnvironment: childEnvironment
        )
    }
}
