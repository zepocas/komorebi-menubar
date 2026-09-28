import Foundation

/// A komorebi config profile is any `komorebi*.json` in the config directory, except the
/// bar configs. The selected profile is exposed as the `active.json` symlink so that restarts
/// (manual or via launchd) always boot the profile that was picked last.
public enum ProfileDiscovery {
    public static let activeLinkName = "active.json"
    public static let defaultProfileName = "komorebi.json"

    public static func isProfile(fileName: String) -> Bool {
        fileName.hasPrefix("komorebi")
            && fileName.hasSuffix(".json")
            && !fileName.hasPrefix("komorebi.bar")
    }

    /// Profile file names, with the default `komorebi.json` first and the rest alphabetical.
    public static func profileNames(in fileNames: [String]) -> [String] {
        fileNames.filter(isProfile).sorted { lhs, rhs in
            if lhs == defaultProfileName { return rhs != defaultProfileName }
            if rhs == defaultProfileName { return false }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    /// `komorebi.json` → "default", `komorebi.work.json` → "work".
    public static func displayName(forProfile fileName: String) -> String {
        var name = fileName
        name.removeFirst("komorebi".count)
        name.removeLast(".json".count)
        let trimmed = name.trimmingCharacters(in: CharacterSet(charactersIn: ".-_ "))
        return trimmed.isEmpty ? "default" : trimmed
    }
}
