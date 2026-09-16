import Foundation

/// Bounded ceiling for cold-launch / session-validation token refresh.
nonisolated enum AuthSessionRefreshTimeout {
    static let defaultNanoseconds: UInt64 = 45_000_000_000

    #if DEBUG
    nonisolated(unsafe) static var overrideNanoseconds: UInt64?
    #endif

    static func activeNanoseconds(configuration: AuthenticationConfiguration) -> UInt64 {
        let seconds = max(5, configuration.coldLaunchRefreshTimeout)
        let configured = UInt64(seconds * 1_000_000_000)
        #if DEBUG
        return overrideNanoseconds ?? configured
        #else
        return configured
        #endif
    }

    static func run<T: Sendable>(
        configuration: AuthenticationConfiguration,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let ceiling = activeNanoseconds(configuration: configuration)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let gate = AuthRefreshResumeGate<T>()

            let work = Task {
                do {
                    let value = try await operation()
                    await gate.resumeOnce(with: .success(value), continuation: continuation)
                } catch is CancellationError {
                    // Timeout owner emits the typed refresh failure.
                } catch {
                    await gate.resumeOnce(with: .failure(error), continuation: continuation)
                }
            }

            Task {
                do {
                    try await Task.sleep(nanoseconds: ceiling)
                    work.cancel()
                    await AuthRefreshSingleFlight.shared.cancelAll()
                    await gate.resumeOnce(
                        with: .failure(AuthenticationError.unknown("refreshTimeout")),
                        continuation: continuation
                    )
                } catch is CancellationError {
                    // Work finished first.
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

private actor AuthRefreshResumeGate<T> {
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
