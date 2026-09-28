import Foundation

// Minimal views of komorebi's JSON. We only decode the fields we render, so unrelated
// schema changes in komorebi don't break the indicator.

/// komorebi's `Ring`: a list plus the index of the focused element.
public struct Ring<Element: Decodable & Sendable>: Decodable, Sendable {
    public let elements: [Element]
    public let focused: Int

    public init(elements: [Element], focused: Int) {
        self.elements = elements
        self.focused = focused
    }
}

public struct KomorebiState: Decodable, Sendable {
    public let monitors: Ring<KomorebiMonitor>

    public init(monitors: Ring<KomorebiMonitor>) {
        self.monitors = monitors
    }
}

public struct KomorebiMonitor: Decodable, Sendable {
    public let workspaces: Ring<KomorebiWorkspace>

    public init(workspaces: Ring<KomorebiWorkspace>) {
        self.workspaces = workspaces
    }
}

public struct KomorebiWorkspace: Decodable, Sendable {
    public let name: String?

    public init(name: String?) {
        self.name = name
    }
}

/// What komorebi writes to a subscriber socket: `{"event": ..., "state": ...}`.
struct KomorebiNotification: Decodable {
    let state: KomorebiState
}

public enum KomorebiDecoder {
    /// Decodes a payload received on a `subscribe-socket` connection.
    public static func state(fromNotification data: Data) throws -> KomorebiState {
        try JSONDecoder().decode(KomorebiNotification.self, from: data).state
    }

    /// Decodes the output of `komorebic state`.
    public static func state(fromStateJSON data: Data) throws -> KomorebiState {
        try JSONDecoder().decode(KomorebiState.self, from: data)
    }
}
