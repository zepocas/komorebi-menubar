import Foundation
import IndicatorCore

/// Manages the `active.json` symlink in the komorebi config directory. The symlink is the single
/// source of truth for the selected profile, so launchd and manual restarts pick it up too.
struct ProfileStore: Sendable {
    let paths: Paths

    func available() -> [URL] {
        let fileNames = (try? FileManager.default.contentsOfDirectory(atPath: paths.configDir.path)) ?? []
        return ProfileDiscovery.profileNames(in: fileNames).map { paths.configDir.appendingPathComponent($0) }
    }

    /// File name the symlink points at, or nil when there is no symlink.
    func activeProfileName() -> String? {
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: paths.activeProfileLink.path) else {
            return nil
        }
        return URL(fileURLWithPath: destination).lastPathComponent
    }

    /// Creates `active.json → komorebi.json` on first run.
    func ensureActiveLink() throws {
        let link = paths.activeProfileLink.path
        let fileManager = FileManager.default
        guard (try? fileManager.attributesOfItem(atPath: link)) == nil else { return }
        guard fileManager.fileExists(atPath: paths.configDir.appendingPathComponent(ProfileDiscovery.defaultProfileName).path) else { return }
        try fileManager.createSymbolicLink(atPath: link, withDestinationPath: ProfileDiscovery.defaultProfileName)
    }

    /// Points `active.json` at `profile`. Refuses to touch an `active.json` that is a real file.
    func activate(_ profile: URL) throws {
        let link = paths.activeProfileLink.path
        let fileManager = FileManager.default
        if let attributes = try? fileManager.attributesOfItem(atPath: link) {
            guard attributes[.type] as? FileAttributeType == .typeSymbolicLink else {
                throw ServiceError(message: "\(link) is a regular file, not a symlink. Move it away so profiles can be switched.")
            }
            try fileManager.removeItem(atPath: link)
        }
        // Relative target so the link keeps working if the config directory moves.
        try fileManager.createSymbolicLink(atPath: link, withDestinationPath: profile.lastPathComponent)
    }
}
