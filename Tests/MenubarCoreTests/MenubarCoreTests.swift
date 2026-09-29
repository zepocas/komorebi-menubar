import Foundation
import Testing
@testable import MenubarCore

@Suite struct DecodingTests {
    @Test func decodesNotificationAndIgnoresUnknownFields() throws {
        let url = try #require(Bundle.module.url(forResource: "notification-two-monitors", withExtension: "json", subdirectory: "Fixtures"))
        let state = try KomorebiDecoder.state(fromNotification: Data(contentsOf: url))

        #expect(state.monitors.focused == 1)
        #expect(state.monitors.elements.count == 2)
        #expect(state.monitors.elements[0].workspaces.focused == 1)
        #expect(state.monitors.elements[1].workspaces.elements[2].name == nil)
    }

    @Test func rejectsTruncatedPayload() {
        #expect(throws: (any Error).self) {
            try KomorebiDecoder.state(fromNotification: Data(#"{"event":{"type":"Show"},"state":{"moni"#.utf8))
        }
    }
}

@Suite struct WorkspaceLabelTests {
    private func state(focusedMonitor: Int, _ monitors: [(names: [String?], focused: Int)]) -> KomorebiState {
        KomorebiState(monitors: Ring(
            elements: monitors.map { monitor in
                KomorebiMonitor(workspaces: Ring(elements: monitor.names.map(KomorebiWorkspace.init(name:)), focused: monitor.focused))
            },
            focused: focusedMonitor
        ))
    }

    @Test func showsEveryMonitorAndMarksTheFocusedOne() {
        let label = WorkspaceLabel(state: state(focusedMonitor: 1, [(["1", "2", "3"], 1), (["4", "5", "6"], 1)]))

        #expect(label.segments == [
            .init(text: "2", isFocusedMonitor: false),
            .init(text: "5", isFocusedMonitor: true),
        ])
        #expect(label.plainText == "2 │ 5")
    }

    @Test func singleMonitorHasNoSeparator() {
        let label = WorkspaceLabel(state: state(focusedMonitor: 0, [(["1", "2", "3"], 2)]))
        #expect(label.plainText == "3")
    }

    @Test func unnamedWorkspacesFallBackToTheirPosition() {
        let label = WorkspaceLabel(state: state(focusedMonitor: 0, [([nil, "", nil], 1), ([nil], 0)]))
        #expect(label.plainText == "2 │ 1")
    }

    @Test func skipsMonitorsWithAnOutOfRangeFocusIndex() {
        let label = WorkspaceLabel(state: state(focusedMonitor: 0, [(["1"], 0), ([], 0)]))
        #expect(label.plainText == "1")
    }
}

@Suite struct ProfileDiscoveryTests {
    @Test func findsProfilesAndSkipsBarAndOtherFiles() {
        let files = ["komorebi.work.json", "applications.json", "komorebi.bar.json", "komorebi.json",
                     "active.json", "skhdrc", "komorebi.bar.2.json", "komorebi.home.json"]
        #expect(ProfileDiscovery.profileNames(in: files) == ["komorebi.json", "komorebi.home.json", "komorebi.work.json"])
    }

    @Test func displayNames() {
        #expect(ProfileDiscovery.displayName(forProfile: "komorebi.json") == "default")
        #expect(ProfileDiscovery.displayName(forProfile: "komorebi.work.json") == "work")
        #expect(ProfileDiscovery.displayName(forProfile: "komorebi-laptop.json") == "laptop")
    }
}

@Suite struct LaunchAgentPlistTests {
    private func plist(_ kind: LaunchAgentPlist.Kind, startsAtLogin: Bool) -> [String: Any] {
        LaunchAgentPlist.make(kind: kind, label: "l", programArguments: ["/bin/x", "-c", "rc"],
                              environment: ["PATH": "/bin"], log: "/tmp/x.log", startsAtLogin: startsAtLogin)
    }

    @Test func offHasNeitherRunAtLoadNorKeepAlive() {
        // Any KeepAlive implies RunAtLoad, so it would start at login anyway.
        for kind in [LaunchAgentPlist.Kind.komorebi, .skhd] {
            let off = plist(kind, startsAtLogin: false)
            #expect(off["RunAtLoad"] == nil)
            #expect(off["KeepAlive"] == nil)
            #expect(!LaunchAgentPlist.startsAtLogin(off))
            #expect(off["ProgramArguments"] as? [String] == ["/bin/x", "-c", "rc"])
        }
    }

    @Test func onKeepsSkhdAliveAndLetsKomorebiStayStopped() {
        let skhd = plist(.skhd, startsAtLogin: true)
        #expect(skhd["RunAtLoad"] as? Bool == true)
        #expect(skhd["KeepAlive"] as? Bool == true)

        let komorebi = plist(.komorebi, startsAtLogin: true)
        #expect(komorebi["KeepAlive"] as? [String: Bool] == ["SuccessfulExit": false])
        #expect(LaunchAgentPlist.startsAtLogin(komorebi))
    }

    @Test func readsPlistsWrittenByTheOldInstallScript() {
        #expect(LaunchAgentPlist.startsAtLogin(["RunAtLoad": true, "KeepAlive": true]))
        #expect(LaunchAgentPlist.startsAtLogin(["KeepAlive": ["SuccessfulExit": false]]))
        #expect(!LaunchAgentPlist.startsAtLogin(["RunAtLoad": false]))
    }
}
