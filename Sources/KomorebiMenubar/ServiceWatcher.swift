import Foundation

/// Polls for the komorebi and skhd processes. A new komorebi PID means a fresh komorebi instance,
/// which has forgotten our subscription, so the owner must subscribe again.
@MainActor
final class ServiceWatcher {
    private(set) var komorebiPID: pid_t?
    private(set) var skhdPID: pid_t?

    var onKomorebiStarted: (() -> Void)?
    var onKomorebiStopped: (() -> Void)?

    private var timer: Timer?

    func start(interval: TimeInterval = 2) {
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        // Common modes keep polling while the menu or an alert is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    func poll() {
        skhdPID = ProcessLookup.pid(named: "skhd")

        let current = ProcessLookup.pid(named: "komorebi")
        guard current != komorebiPID else { return }
        komorebiPID = current
        if current == nil {
            onKomorebiStopped?()
        } else {
            onKomorebiStarted?()
        }
    }
}
