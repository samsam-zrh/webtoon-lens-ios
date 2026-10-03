import Foundation

public actor PublicChapterActivity {
    private var active = true
    private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]
    public var waitingCount: Int { waiters.count }

    public init() {}

    public func setActive(_ active: Bool) {
        self.active = active
        if active {
            let pending = waiters.values
            waiters.removeAll()
            pending.forEach { $0.resume() }
        }
    }

    public func waitUntilActive() async throws {
        try Task.checkCancellation()
        guard !active else { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters[id] = continuation
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
        try Task.checkCancellation()
    }

    private func cancel(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }
}
