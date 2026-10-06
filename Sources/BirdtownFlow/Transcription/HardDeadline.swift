import Foundation
import os

/// Bounds how long the app waits for work it doesn't control: a cloud request, the on-device
/// language model, a CoreML pass.
///
/// Deliberately not a task group. A group can't return until every child has finished, so a
/// child that ignores cancellation (a blocking CoreML prediction, a framework call that never
/// checks `Task.isCancelled`) would hold the caller past its deadline, which is exactly the
/// stall a timeout exists to prevent. Here the work runs in its own task, the caller resumes
/// with whichever finishes first, and the loser is cancelled and its result dropped.
enum HardDeadline {
    /// The work didn't finish in time.
    struct Exceeded: Error {}

    static func run<T: Sendable>(
        within limit: Duration,
        _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let gate = ResumeGate<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                gate.install(continuation)
                let worker = Task {
                    do {
                        gate.finish(.success(try await work()))
                    } catch {
                        gate.finish(.failure(error))
                    }
                }
                let timer = Task {
                    try? await Task.sleep(for: limit)
                    gate.finish(.failure(Exceeded()))
                }
                gate.attach([worker, timer])
            }
        } onCancel: {
            gate.finish(.failure(CancellationError()))
        }
    }
}

/// Resumes a continuation exactly once, whoever gets there first (the work, the timer or the
/// caller's cancellation), then cancels the tasks still running.
private final class ResumeGate<T: Sendable>: Sendable {
    private enum Phase: Sendable {
        /// No continuation yet and no result.
        case idle
        case waiting(CheckedContinuation<T, Error>)
        /// A result arrived before the continuation was installed (the caller was already
        /// cancelled on entry).
        case early(Result<T, Error>)
        case done
    }

    private struct State: Sendable {
        var phase: Phase = .idle
        var tasks: [Task<Void, Never>] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func install(_ continuation: CheckedContinuation<T, Error>) {
        let early: Result<T, Error>? = state.withLock { state in
            if case .early(let result) = state.phase {
                state.phase = .done
                return result
            }
            state.phase = .waiting(continuation)
            return nil
        }
        if let early { continuation.resume(with: early) }
    }

    func attach(_ tasks: [Task<Void, Never>]) {
        let alreadyDone = state.withLock { state -> Bool in
            if case .done = state.phase { return true }
            state.tasks = tasks
            return false
        }
        if alreadyDone { tasks.forEach { $0.cancel() } }
    }

    func finish(_ result: Result<T, Error>) {
        let (continuation, tasks) = state.withLock { state -> (CheckedContinuation<T, Error>?, [Task<Void, Never>]) in
            switch state.phase {
            case .idle:
                state.phase = .early(result)
                return (nil, [])
            case .waiting(let continuation):
                state.phase = .done
                let tasks = state.tasks
                state.tasks = []
                return (continuation, tasks)
            case .early, .done:
                return (nil, [])
            }
        }
        continuation?.resume(with: result)
        tasks.forEach { $0.cancel() }
    }
}
