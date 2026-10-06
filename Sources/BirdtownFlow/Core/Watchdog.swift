import Foundation

/// Time limits for async work that might never come back.
enum Watchdog {
    /// Thrown by `run` when the limit passes first.
    struct Expired: Error {}

    /// Runs `operation`, giving up after `limit`.
    ///
    /// Unlike a task group — which waits for every child before returning — this returns the
    /// moment the limit passes even if `operation` ignores cancellation: it is cancelled and
    /// left to wind down on its own. That is the point: a wedged speech engine must not be able
    /// to hold the dictation state machine hostage. Cancelling the caller cancels it too.
    static func run<T: Sendable>(
        within limit: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let gate = DeadlineGate<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                gate.install(continuation)
                gate.track(Task {
                    do {
                        gate.finish(.success(try await operation()))
                    } catch {
                        gate.finish(.failure(error))
                    }
                })
                gate.track(Task {
                    try? await Task.sleep(for: limit)
                    gate.finish(.failure(Expired()))
                })
            }
        } onCancel: {
            gate.finish(.failure(CancellationError()))
        }
    }
}

/// Resumes the continuation exactly once — with whichever of the work, the timer or a
/// cancellation comes first — then cancels the others.
///
/// `@unchecked Sendable` is sound because every mutable stored property is read and written
/// only while holding `lock`.
private final class DeadlineGate<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    /// A result that arrived before the continuation was installed (an early cancellation).
    private var early: Result<T, Error>?
    private var tasks: [Task<Void, Never>] = []
    private var isFinished = false

    func install(_ continuation: CheckedContinuation<T, Error>) {
        let result: Result<T, Error>? = lock.withLock {
            if let early { return early }
            self.continuation = continuation
            return nil
        }
        if let result { continuation.resume(with: result) }
    }

    func track(_ task: Task<Void, Never>) {
        let cancelNow = lock.withLock {
            if isFinished { return true }
            tasks.append(task)
            return false
        }
        if cancelNow { task.cancel() }
    }

    func finish(_ result: Result<T, Error>) {
        let (continuation, others): (CheckedContinuation<T, Error>?, [Task<Void, Never>]) = lock.withLock {
            guard !isFinished else { return (nil, []) }
            isFinished = true
            let continuation = self.continuation
            self.continuation = nil
            if continuation == nil { early = result }
            let others = tasks
            tasks = []
            return (continuation, others)
        }
        continuation?.resume(with: result)
        for task in others { task.cancel() }
    }
}
