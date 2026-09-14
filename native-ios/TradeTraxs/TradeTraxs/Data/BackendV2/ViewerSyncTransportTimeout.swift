import Foundation

/// Short transport ceiling for the lightweight viewer sync fingerprint RPC.
///
/// Missing/un deployed production RPCs must fail fast — never block cold launch for 45s.
nonisolated enum ViewerSyncTransportTimeout {
    static let defaultNanoseconds: UInt64 = 5_000_000_000

    #if DEBUG
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
            let gate = ViewerSyncResumeGate<T>()

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
                        with: .failure(BackendV2RPCError.transport("viewer sync timeout")),
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
}

private actor ViewerSyncResumeGate<T> {
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
