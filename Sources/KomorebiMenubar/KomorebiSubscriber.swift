import Foundation
import MenubarCore

/// Listens on a Unix socket in komorebi's data directory. After `komorebic subscribe-socket <name>`,
/// komorebi opens one connection per event, writes a single `{event, state}` JSON document (no
/// newline framing) and closes it, so each connection is read until EOF and decoded on its own.
final class KomorebiSubscriber: @unchecked Sendable {
    static let socketName = "komorebi-menubar.sock"

    private let socketPath: String
    private let queue = DispatchQueue(label: "io.github.zepocas.komorebi-menubar.subscriber")
    private let onState: @Sendable (KomorebiState) -> Void
    private var listenFD: Int32 = -1
    private var source: DispatchSourceRead?

    init(dataDir: URL, onState: @escaping @Sendable (KomorebiState) -> Void) {
        socketPath = dataDir.appendingPathComponent(Self.socketName).path
        self.onState = onState
    }

    func start() throws {
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SubscriberError.posix("socket", errno) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            throw SubscriberError.pathTooLong(socketPath)
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: pathBytes) }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            close(fd)
            throw SubscriberError.posix("bind", code)
        }
        guard listen(fd, 16) == 0 else {
            let code = errno
            close(fd)
            throw SubscriberError.posix("listen", code)
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        listenFD = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
        unlink(socketPath)
    }

    private func acceptPending() {
        while true {
            let client = accept(listenFD, nil, nil)
            guard client >= 0 else { return } // EAGAIN: nothing left to accept
            read(client)
        }
    }

    private func read(_ client: Int32) {
        defer { close(client) }

        // Accepted sockets inherit O_NONBLOCK on macOS; read this one blocking with a timeout instead.
        _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var payload = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = Darwin.read(client, &buffer, buffer.count)
            guard count > 0 else { break }
            payload.append(buffer, count: count)
        }

        if let state = try? KomorebiDecoder.state(fromNotification: payload) {
            onState(state)
        }
    }
}

enum SubscriberError: LocalizedError {
    case posix(String, Int32)
    case pathTooLong(String)

    var errorDescription: String? {
        switch self {
        case let .posix(call, code): "\(call) failed: \(String(cString: strerror(code)))"
        case let .pathTooLong(path): "socket path is too long: \(path)"
        }
    }
}
