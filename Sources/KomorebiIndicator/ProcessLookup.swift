import Darwin

/// Finds processes by exact executable name via libproc. Cheap enough to poll every few seconds,
/// and unlike probing komorebi.sock it doesn't make komorebi log a malformed-message error.
enum ProcessLookup {
    static func pid(named name: String) -> pid_t? {
        let estimated = proc_listallpids(nil, 0)
        guard estimated > 0 else { return nil }

        var pids = [pid_t](repeating: 0, count: Int(estimated) + 64)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard count > 0 else { return nil }

        var nameBuffer = [CChar](repeating: 0, count: Int(MAXCOMLEN) * 2 + 1)
        for pid in pids.prefix(Int(count)) where pid > 0 {
            guard proc_name(pid, &nameBuffer, UInt32(nameBuffer.count)) > 0 else { continue }
            let bytes = nameBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            if String(decoding: bytes, as: UTF8.self) == name {
                return pid
            }
        }
        return nil
    }
}
