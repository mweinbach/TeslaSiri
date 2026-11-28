/// Bookkeeping for an app-owned animation engine. This does not animate views,
/// infer native split progress, or establish that an animation has completed.
/// Call finish only from the engine event that satisfies your settled contract.
@MainActor
final class MotionRequestState {
    enum Endpoint: Equatable, Sendable {
        case collapsed
        case expanded

        var progress: Double { self == .expanded ? 1 : 0 }
    }

    struct Request: Equatable, Sendable {
        fileprivate let revision: UInt64
        let destination: Endpoint
    }

    enum Phase: Equatable {
        case detached
        case settled(Endpoint)
        case moving(Request)
        case interrupted
    }

    private var revision: UInt64 = 0
    private(set) var target: Endpoint = .collapsed
    private(set) var observedProgress: Double?
    private(set) var phase: Phase = .detached

    /// The caller must first establish this actual visual endpoint.
    func attach(settledAt endpoint: Endpoint) {
        revision += 1
        target = endpoint
        observedProgress = endpoint.progress
        phase = .settled(endpoint)
    }

    /// Prepare state BEFORE calling the engine: completion may be immediate.
    /// A repeated live destination is a no-op; an interrupted request can resume.
    func request(_ destination: Endpoint) -> Request? {
        guard phase != .detached else { return nil }
        guard destination != target || phase == .interrupted else { return nil }
        revision += 1
        target = destination
        let request = Request(revision: revision, destination: destination)
        phase = .moving(request)
        return request
    }

    /// Measurements are independent of intent and completion bookkeeping.
    func observe(progress: Double) {
        guard phase != .detached, progress.isFinite else { return }
        observedProgress = min(1, max(0, progress))
    }

    /// Old, cancelled, duplicate, or detached completions have no effect.
    @discardableResult
    func finish(_ request: Request) -> Bool {
        guard revision == request.revision,
              target == request.destination,
              phase == .moving(request) else { return false }
        phase = .settled(request.destination)
        return true
    }

    /// Invalidate completion before cancelling/holding the owning engine.
    /// This bookkeeping alone does not freeze a view's presentation.
    func interrupt() {
        guard phase != .detached else { return }
        revision += 1
        phase = .interrupted
    }

    func detach() {
        revision += 1
        observedProgress = nil
        phase = .detached
    }
}
