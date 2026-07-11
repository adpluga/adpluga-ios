import Foundation

actor FeaturesCache {
    private let transport: HttpTransport
    private var onUpgrade: (@Sendable (String?) -> Void)?
    private var _current: FeaturesView = .empty
    private var _etag: String?
    private var _lastFetchMs: Int64 = 0
    private var listeners: [UUID: (FeaturesView) -> Void] = [:]
    private var revalidatorTask: Task<Void, Never>?
    private var inflight: Task<Void, Error>?

    init(transport: HttpTransport) {
        self.transport = transport
    }

    var current: FeaturesView { _current }

    func setOnUpgradeRequired(_ fn: @escaping @Sendable (String?) -> Void) {
        onUpgrade = fn
    }

    @discardableResult
    func addListener(_ fn: @escaping (FeaturesView) -> Void) -> UUID {
        let id = UUID()
        listeners[id] = fn
        return id
    }

    func removeListener(_ id: UUID) {
        listeners.removeValue(forKey: id)
    }

    func start() {
        if revalidatorTask != nil { return }
        revalidatorTask = Task { [weak self] in
            while !Task.isCancelled {
                let ns = UInt64(Constants.featuresRevalidateMs) * 1_000_000
                try? await Task.sleep(nanoseconds: ns)
                if Task.isCancelled { break }
                do {
                    try await self?.ensure(force: true)
                } catch {
                    AdPlugaLogger.debug("features revalidate failed", error: error)
                }
            }
        }
    }

    func stop() {
        revalidatorTask?.cancel()
        revalidatorTask = nil
        inflight?.cancel()
        inflight = nil
    }

    func ensure(force: Bool = false) async throws {
        let now = Self.nowMs()
        if !force && (now - _lastFetchMs) < Int64(Constants.featuresMinIntervalMs) {
            return
        }
        if let inflight = inflight {
            try await inflight.value
            return
        }
        let task: Task<Void, Error> = Task { [weak self] in
            try await self?.doFetch()
        }
        inflight = task
        do {
            try await task.value
            inflight = nil
        } catch {
            inflight = nil
            throw error
        }
    }

    private func doFetch() async throws {
        let etag = _etag
        do {
            let result = try await transport.fetchFeatures(etag: etag)
            _lastFetchMs = Self.nowMs()
            switch result {
            case .notModified:
                return
            case .updated(let view, let newEtag):
                _current = view
                _etag = newEtag
                let snapshot = Array(listeners.values)
                for fn in snapshot {
                    fn(view)
                }
            }
        } catch let err as AdPlugaError {
            if case .upgradeRequired(let min) = err {
                onUpgrade?(min)
                return
            }
            throw err
        }
    }

    private static func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
