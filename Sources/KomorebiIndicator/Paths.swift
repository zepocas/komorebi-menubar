import Foundation
import IndicatorCore

/// Absolute locations of binaries and config. GUI apps (and launchd jobs) don't get the shell's
/// PATH, so `~/.local/bin` etc. are searched explicitly instead of relying on the environment.
struct Paths: Sendable {
    let home: URL
    let configDir: URL
    let dataDir: URL
    let komorebic: URL
    let launchctl = URL(fileURLWithPath: "/bin/launchctl")
    /// Environment handed to every child process.
    let childEnvironment: [String: String]

    var activeProfileLink: URL { configDir.appendingPathComponent(ProfileDiscovery.activeLinkName) }

    static func resolve() -> Paths {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let environment = ProcessInfo.processInfo.environment

        let configDir = environment["KOMOREBI_CONFIG_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? home.appendingPathComponent(".config/komorebi", isDirectory: true)

        let searchDirs = [home.appendingPathComponent(".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin"]
            + (environment["PATH"]?.split(separator: ":").map(String.init) ?? [])
            + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        func find(_ name: String, fallback: String) -> URL {
            let match = searchDirs
                .map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
                .first { fileManager.isExecutableFile(atPath: $0.path) }
            return match ?? URL(fileURLWithPath: fallback)
        }

        var childEnvironment = environment
        childEnvironment["PATH"] = Array(NSOrderedSet(array: searchDirs)).compactMap { $0 as? String }.joined(separator: ":")
        childEnvironment["KOMOREBI_CONFIG_HOME"] = configDir.path

        return Paths(
            home: home,
            configDir: configDir,
            dataDir: home.appendingPathComponent("Library/Application Support/komorebi", isDirectory: true),
            komorebic: find("komorebic", fallback: home.appendingPathComponent(".local/bin/komorebic").path),
            childEnvironment: childEnvironment
        )
    }
}
