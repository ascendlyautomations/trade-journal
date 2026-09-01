import Foundation

/// Bounded transport timeout for Session/Dashboard bootstrap RPC paths.
nonisolated enum BootstrapTransportTimeout {
    /// Default bootstrap ceiling — prevents indefinitely suspended RPC tasks.
    static let defaultNanoseconds: UInt64 = 45_000_000_000

    #if DEBUG
    /// Test hook — set to a short value in unit tests; never in production builds.
    nonisolated(unsafe) static var overrideNanoseconds: UInt64?
    #endif

    static var activeNanoseconds: UInt64 {
        #if DEBUG
        overrideNanoseconds ?? defaultNanoseconds
        #else
        defaultNanoseconds
        #endif
    }

    static func run<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let gate = ResumeGate<T>()

            let work = Task {
                do {
                    let value = try await operation()
                    await gate.resumeOnce(with: .success(value), continuation: continuation)
                } catch is CancellationError {
                    // Timeout owner emits the typed transport failure.
                } catch {
                    await gate.resumeOnce(with: .failure(error), continuation: continuation)
                }
            }

            Task {
                do {
                    try await Task.sleep(nanoseconds: activeNanoseconds)
                    work.cancel()
                    await gate.resumeOnce(
                        with: .failure(BackendV2RPCError.transport("bootstrap timeout")),
                        continuation: continuation
                    )
                } catch is CancellationError {
                    // Work finished first — gate already resumed.
                } catch {
                    await gate.resumeOnce(with: .failure(error), continuation: continuation)
                }
            }
        }
    }

    #if DEBUG
    static func withTestTimeout<T>(
        _ nanoseconds: UInt64,
        _ body: () async throws -> T
    ) async rethrows -> T {
        let previous = overrideNanoseconds
        overrideNanoseconds = nanoseconds
        defer { overrideNanoseconds = previous }
        return try await body()
    }
    #endif
}

private actor ResumeGate<T> {
    private var resumed = false

    func resumeOnce(
        with result: Result<T, Error>,
        continuation: CheckedContinuation<T, Error>
    ) {
        guard !resumed else { return }
        resumed = true
        continuation.resume(with: result)
    }
}
