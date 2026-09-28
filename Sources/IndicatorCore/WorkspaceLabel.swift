/// The text shown in the menubar: one segment per monitor, in monitor index order.
public struct WorkspaceLabel: Equatable, Sendable {
    public struct Segment: Equatable, Sendable {
        public let text: String
        public let isFocusedMonitor: Bool

        public init(text: String, isFocusedMonitor: Bool) {
            self.text = text
            self.isFocusedMonitor = isFocusedMonitor
        }
    }

    public static let separator = " │ "

    public let segments: [Segment]

    public init(segments: [Segment]) {
        self.segments = segments
    }

    public init(state: KomorebiState) {
        let focusedMonitor = state.monitors.focused
        segments = state.monitors.elements.enumerated().compactMap { monitorIndex, monitor in
            let workspaces = monitor.workspaces
            guard workspaces.elements.indices.contains(workspaces.focused) else { return nil }
            return Segment(
                text: Self.displayName(workspaces.elements[workspaces.focused], index: workspaces.focused),
                isFocusedMonitor: monitorIndex == focusedMonitor
            )
        }
    }

    public var plainText: String {
        segments.map(\.text).joined(separator: Self.separator)
    }

    /// Unnamed workspaces fall back to their 1-based position, like komorebi-bar does.
    static func displayName(_ workspace: KomorebiWorkspace, index: Int) -> String {
        if let name = workspace.name, !name.isEmpty {
            return name
        }
        return String(index + 1)
    }
}
