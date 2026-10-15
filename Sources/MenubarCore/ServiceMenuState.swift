/// What a service's menu row shows: "name — status", and a submenu with Stop / Start and Restart.
public struct ServiceMenuState: Equatable, Sendable {
    public let status: String
    public let isRunning: Bool
    public let toggleTitle: String
    /// Stop when running, otherwise Start.
    public let toggleStops: Bool
    public let isToggleEnabled: Bool
    public let isRestartEnabled: Bool

    /// - Parameters:
    ///   - pid: the service's process id, nil when it isn't running.
    ///   - activity: progress verb of an action in flight, e.g. "restarting".
    public init(pid: Int32?, activity: String?) {
        let running = pid != nil
        let idle = activity == nil
        isRunning = running
        toggleStops = running
        toggleTitle = running ? "Stop" : "Start"
        // Everything is locked while an action runs; Restart also needs something to restart.
        isToggleEnabled = idle
        isRestartEnabled = running && idle
        status = activity.map { "\($0)…" } ?? pid.map { "running (pid \($0))" } ?? "not running"
    }
}
