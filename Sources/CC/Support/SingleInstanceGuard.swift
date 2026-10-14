import Darwin
import Foundation

final class SingleInstanceGuard {
    private static let processLock = NSLock()
    private static var ownedIdentifiers: Set<String> = []

    private let fileDescriptor: Int32
    private let identifier: String

    init?(identifier: String) {
        guard Self.claimInCurrentProcess(identifier) else { return nil }

        let lockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(identifier).lock", isDirectory: false)
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)

        guard descriptor >= 0 else {
            Self.releaseInCurrentProcess(identifier)
            return nil
        }
        var lock = flock()
        lock.l_type = Int16(F_WRLCK)
        lock.l_whence = Int16(SEEK_SET)

        guard Darwin.fcntl(descriptor, F_SETLK, &lock) == 0 else {
            Darwin.close(descriptor)
            Self.releaseInCurrentProcess(identifier)
            return nil
        }

        fileDescriptor = descriptor
        self.identifier = identifier
    }

    deinit {
        var lock = flock()
        lock.l_type = Int16(F_UNLCK)
        lock.l_whence = Int16(SEEK_SET)
        _ = Darwin.fcntl(fileDescriptor, F_SETLK, &lock)
        Darwin.close(fileDescriptor)
        Self.releaseInCurrentProcess(identifier)
    }

    private static func claimInCurrentProcess(_ identifier: String) -> Bool {
        processLock.lock()
        defer { processLock.unlock() }
        return ownedIdentifiers.insert(identifier).inserted
    }

    private static func releaseInCurrentProcess(_ identifier: String) {
        processLock.lock()
        ownedIdentifiers.remove(identifier)
        processLock.unlock()
    }
}
