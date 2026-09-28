import Foundation

struct ShellResult: Sendable {
    let status: Int32
    let stdout: Data
    let stderr: String

    var succeeded: Bool { status == 0 }
}

enum Shell {
    /// Runs a short-lived command to completion off the main thread.
    ///
    /// Don't use this for commands that leave a daemon behind (e.g. `komorebic start`): the daemon
    /// inherits the pipes and reading to EOF would block until it exits.
    static func run(_ executable: URL, _ arguments: [String], environment: [String: String]) async -> ShellResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                process.environment = environment
                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr
                process.standardInput = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: ShellResult(status: -1, stdout: Data(), stderr: "\(executable.path): \(error.localizedDescription)"))
                    return
                }

                // Drain stderr on another thread so a chatty command can't fill one pipe and deadlock.
                let stderrData = ThreadSafeBox(Data())
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    stderrData.value = stderr.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()

                continuation.resume(returning: ShellResult(
                    status: process.terminationStatus,
                    stdout: stdoutData,
                    stderr: String(decoding: stderrData.value, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                ))
            }
        }
    }
}

private final class ThreadSafeBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) { storage = value }

    var value: Value {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }
}
