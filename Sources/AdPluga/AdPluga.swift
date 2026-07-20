import Foundation

public final class AdPluga: @unchecked Sendable {
    private static let stateLock = NSLock()
    private static var _instance: AdPluga?

    public static var instance: AdPluga {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let inst = _instance else {
            fatalError("AdPluga.initialize must be called before AdPluga.instance")
        }
        return inst
    }

    public static var maybeInstance: AdPluga? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _instance
    }

    let publisherKey: String
    let endpoint: URL
    let consentStore: ConsentStore
    let transport: HttpTransport
    let features: FeaturesCache
    let telemetry: TelemetryBatcher

    private let onUpgradeRequired: ((String?) -> Void)?
    private let upgradeLock = NSLock()
    private var upgradeBlocked = false
    private var upgradeNotified = false
    private var destroyed = false

    private let eventsLock = NSLock()
    private var eventContinuations: [UUID: AsyncStream<SdkEvent>.Continuation] = [:]

    public var events: AsyncStream<SdkEvent> {
        AsyncStream(bufferingPolicy: .bufferingNewest(128)) { continuation in
            let id = UUID()
            self.eventsLock.lock()
            self.eventContinuations[id] = continuation
            self.eventsLock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self = self else { return }
                self.eventsLock.lock()
                self.eventContinuations.removeValue(forKey: id)
                self.eventsLock.unlock()
            }
        }
    }

    private init(
        publisherKey: String,
        endpoint: URL,
        initialConsent: ConsentState,
        telemetryEnabled: Bool,
        session: URLSession,
        onUpgradeRequired: ((String?) -> Void)?
    ) {
        self.publisherKey = publisherKey
        self.endpoint = endpoint
        self.consentStore = ConsentStore(initial: initialConsent)
        self.transport = HttpTransport(publisherKey: publisherKey, endpoint: endpoint, session: session, consent: consentStore)
        self.features = FeaturesCache(transport: transport)
        self.telemetry = TelemetryBatcher(transport: transport, enabled: telemetryEnabled)
        self.onUpgradeRequired = onUpgradeRequired
    }

    private func start(userTelemetryEnabled: Bool) {
        let features = self.features
        let telemetry = self.telemetry
        Task { [weak self] in
            guard let self = self else { return }
            await features.setOnUpgradeRequired { [weak self] minVersion in
                self?.handleUpgrade(minVersion: minVersion)
            }
            await features.addListener { [weak self] view in
                guard let self = self else { return }
                let remote = view.flag("sdk_telemetry", fallback: true)
                Task { await telemetry.setEnabled(remote && userTelemetryEnabled) }
                self.emit(.featuresUpdated(view: view, at: Date()))
            }
            await features.start()
            await telemetry.start()
            await telemetry.record(type: .initEvent)
            self.emit(.initCompleted(at: Date()))
        }
    }

    public func serve(slotId: String, format: String? = nil, userHash: String? = nil) async -> ServeResponse? {
        upgradeLock.lock()
        if upgradeBlocked {
            upgradeLock.unlock()
            return nil
        }
        upgradeLock.unlock()

        let startMs = Self.nowMs()
        await telemetry.record(type: .serveRequest)
        do {
            let response = try await transport.serve(slotId: slotId, format: format, userHash: userHash)
            let latency = Int(Self.nowMs() - startMs)
            await telemetry.record(type: .serveResponse, latencyMs: latency)
            emit(.adServed(slotId: slotId, ad: response.ad, at: Date()))
            return response
        } catch let err as AdPlugaError {
            if case .upgradeRequired(let minVersion) = err {
                handleUpgrade(minVersion: minVersion)
                return nil
            }
            await telemetry.record(type: .error)
            emit(.adFailed(slotId: slotId, at: Date(), message: err.errorDescription ?? "network"))
            return nil
        } catch {
            await telemetry.record(type: .error)
            emit(.adFailed(slotId: slotId, at: Date(), message: String(describing: error)))
            return nil
        }
    }

    public func fireImpression(slotId: String, ad: Ad, url: String? = nil, token: String) {
        Task {
            if let url = url {
                await transport.beacon(url: url)
            } else {
                await transport.postTrack(kind: "impression", payload: [
                    "slot_id": slotId,
                    "ad_id": ad.id,
                    "impression_token": token,
                ])
            }
            await telemetry.record(type: .impression)
            emit(.impression(slotId: slotId, adId: ad.id, at: Date()))
        }
    }

    public func fireViewable(slotId: String, ad: Ad, token: String) {
        _ = slotId
        _ = ad
        Task {
            await transport.postTrackViewable(token: token)
        }
    }

    public func fireClick(slotId: String, ad: Ad, url: String? = nil, token: String?) {
        Task {
            if let url = url {
                await transport.beacon(url: url)
            } else if let token = token {
                await transport.postTrack(kind: "click", payload: [
                    "slot_id": slotId,
                    "ad_id": ad.id,
                    "click_token": token,
                ])
            }
            await telemetry.record(type: .click)
            emit(.click(slotId: slotId, adId: ad.id, at: Date()))
        }
    }

    public func conversion(payload: [String: Any]) {
        let payload = payload
        Task {
            await transport.postTrack(kind: "conversion", payload: payload)
        }
    }

    public func setConsent(_ state: ConsentState) {
        if consentStore.update(state) {
            emit(.consentChanged(state: state, at: Date()))
        }
    }

    public func ensureFeatures() async {
        do {
            try await features.ensure(force: true)
        } catch {
            AdPlugaLogger.debug("ensureFeatures failed", error: error)
        }
    }

    public var featuresView: FeaturesView {
        get async { await features.current }
    }

    public func flushTelemetry() async {
        try? await telemetry.flush()
    }

    public func destroy() {
        upgradeLock.lock()
        if destroyed {
            upgradeLock.unlock()
            return
        }
        destroyed = true
        upgradeLock.unlock()

        let features = self.features
        let telemetry = self.telemetry
        Task {
            await features.stop()
            await telemetry.stop()
        }

        eventsLock.lock()
        let continuations = Array(eventContinuations.values)
        eventContinuations.removeAll()
        eventsLock.unlock()
        for cont in continuations {
            cont.finish()
        }

        Self.stateLock.lock()
        if Self._instance === self {
            Self._instance = nil
        }
        Self.stateLock.unlock()
    }

    private func handleUpgrade(minVersion: String?) {
        upgradeLock.lock()
        upgradeBlocked = true
        let alreadyNotified = upgradeNotified
        upgradeNotified = true
        upgradeLock.unlock()
        if !alreadyNotified {
            onUpgradeRequired?(minVersion)
            emit(.upgradeRequired(minVersion: minVersion, at: Date()))
        }
    }

    private func emit(_ event: SdkEvent) {
        eventsLock.lock()
        let snapshot = Array(eventContinuations.values)
        eventsLock.unlock()
        for cont in snapshot {
            cont.yield(event)
        }
    }

    private static func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    @discardableResult
    public static func initialize(
        publisherKey: String,
        endpoint: String? = nil,
        consent: ConsentState = .default,
        telemetryEnabled: Bool = true,
        onUpgradeRequired: ((String?) -> Void)? = nil,
        sessionOverride: URLSession? = nil
    ) throws -> AdPluga {
        let range = NSRange(publisherKey.startIndex..., in: publisherKey)
        if Constants.keyPattern.firstMatch(in: publisherKey, options: [], range: range) == nil {
            throw AdPlugaError.invalidKey(publisherKey)
        }
        let normalized = (endpoint ?? Constants.defaultEndpoint)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: normalized), url.scheme?.hasPrefix("http") == true else {
            throw AdPlugaError.invalidKey("endpoint invalid: \(normalized)")
        }
        let session = sessionOverride ?? URLSession(configuration: .default)
        stateLock.lock()
        if let existing = _instance {
            stateLock.unlock()
            return existing
        }
        let pluga = AdPluga(
            publisherKey: publisherKey,
            endpoint: url,
            initialConsent: consent,
            telemetryEnabled: telemetryEnabled,
            session: session,
            onUpgradeRequired: onUpgradeRequired
        )
        _instance = pluga
        stateLock.unlock()
        pluga.start(userTelemetryEnabled: telemetryEnabled)
        return pluga
    }
}
