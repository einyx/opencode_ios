import Foundation

nonisolated protocol CarLiveMonotonicClock: Sendable {
    func now() -> ContinuousClock.Instant
    func sleep(until deadline: ContinuousClock.Instant) async throws
}

nonisolated struct CarLiveContinuousClock: CarLiveMonotonicClock {
    func now() -> ContinuousClock.Instant { .now }

    func sleep(until deadline: ContinuousClock.Instant) async throws {
        try await Task.sleep(until: deadline, clock: .continuous)
    }
}

nonisolated enum CarLiveCloseBudget {
    static func exceeded(now: ContinuousClock.Instant, deadline: ContinuousClock.Instant) -> Bool {
        now >= deadline
    }

    static func remainingMS(now: ContinuousClock.Instant, deadline: ContinuousClock.Instant) -> Int {
        let remaining = now.duration(to: deadline)
        if remaining <= .zero { return 0 }
        let parts = remaining.components
        let ms = parts.seconds * 1_000 + parts.attoseconds / 1_000_000_000_000_000
        return Int(max(0, ms))
    }
}

nonisolated final class CarLiveDeadlineHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var operation: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var settled = false

    static func run(
        until deadline: ContinuousClock.Instant,
        clock: any CarLiveMonotonicClock = CarLiveContinuousClock(),
        operation work: @escaping @Sendable () async -> Void
    ) async -> Bool {
        let handle = CarLiveDeadlineHandle()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                handle.begin(continuation, deadline: deadline, clock: clock, work: work)
            }
        } onCancel: {
            handle.settle(false)
        }
    }

    private func begin(
        _ continuation: CheckedContinuation<Bool, Never>,
        deadline: ContinuousClock.Instant,
        clock: any CarLiveMonotonicClock,
        work: @escaping @Sendable () async -> Void
    ) {
        lock.lock()
        if settled {
            lock.unlock()
            continuation.resume(returning: false)
            return
        }
        self.continuation = continuation
        lock.unlock()
        if CarLiveCloseBudget.exceeded(now: clock.now(), deadline: deadline) {
            settle(false)
            return
        }
        let operation = Task {
            await work()
            self.settle(true)
        }
        let timer = Task {
            do {
                try await clock.sleep(until: deadline)
            } catch {
                self.settle(false)
                return
            }
            self.settle(false)
        }
        lock.lock()
        if settled {
            lock.unlock()
            operation.cancel()
            timer.cancel()
            return
        }
        self.operation = operation
        self.timer = timer
        lock.unlock()
    }

    private func settle(_ value: Bool) {
        let continuation: CheckedContinuation<Bool, Never>?
        let operation: Task<Void, Never>?
        let timer: Task<Void, Never>?
        lock.lock()
        if settled {
            lock.unlock()
            return
        }
        settled = true
        continuation = self.continuation
        self.continuation = nil
        operation = self.operation
        timer = self.timer
        self.operation = nil
        self.timer = nil
        lock.unlock()
        operation?.cancel()
        timer?.cancel()
        continuation?.resume(returning: value)
    }
}
