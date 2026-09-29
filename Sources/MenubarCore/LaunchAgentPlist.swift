import Foundation

/// The LaunchAgent plists this app writes into ~/Library/LaunchAgents.
///
/// Any `KeepAlive` implies `RunAtLoad` (launchd.plist(5)), so an agent that shouldn't start at
/// login must have neither. komorebi's and skhd's plists stay installed even then: the menu starts
/// and restarts them through launchd, and a loaded job with neither key waits to be kickstarted.
public enum LaunchAgentPlist {
    public enum Kind: Sendable {
        case menubar, komorebi, skhd
    }

    public static func make(
        kind: Kind,
        label: String,
        programArguments: [String],
        environment: [String: String],
        log: String,
        startsAtLogin: Bool
    ) -> [String: Any] {
        var plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": programArguments,
            "EnvironmentVariables": environment,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
            "StandardOutPath": log,
            "StandardErrorPath": log,
        ]
        if kind != .menubar {
            plist["ThrottleInterval"] = 10
        }
        if startsAtLogin {
            plist["RunAtLoad"] = true
            // skhd is always kept running. komorebi and the app restart after a crash, but stay
            // stopped after `komorebic stop` or Quit, which exit cleanly.
            plist["KeepAlive"] = kind == .skhd ? true : ["SuccessfulExit": false]
        }
        return plist
    }

    public static func startsAtLogin(_ plist: [String: Any]) -> Bool {
        plist["RunAtLoad"] as? Bool == true || plist["KeepAlive"] != nil
    }
}
