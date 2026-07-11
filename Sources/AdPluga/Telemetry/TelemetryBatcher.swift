import Foundation
import Security

public enum SdkEventType: String, CaseIterable, Sendable {
    case initEvent = "init"
    case serveRequest = "serve_request"
    case serveResponse = "serve_response"
    case impression
    case click
    case error

    var wire: String { rawValue }
}

actor TelemetryBatcher {
    private let transport: HttpTransport

    private final class Bucket {
        var count: Int = 0
        var latencies: [Int] = []
    }

    private var buckets: [SdkEventType: Bucket] = [:]
    private var enabled: Bool
    private var totalRecorded: Int = 0
    private var flushTask: Task<Void, Never>?
    private var flushIntervalMs: Int
    private var randomInt: (Int) -> Int

    init(transport: HttpTransport, enabled: Bool, flushIntervalMs: Int = Constants.telemetryFlushIntervalMs) {
        self.transport = transport
        self.enabled = enabled
        self.flushIntervalMs = flushIntervalMs
        self.randomInt = { Int.random(in: 0..<max($0, 1)) }
    }

    func setEnabled(_ value: Bool) {
        if enabled == value { return }
        enabled = value
        if !value {
            buckets.removeAll()
            totalRecorded = 0
        }
    }

    func setRandomInt(_ fn: @escaping (Int) -> Int) {
        randomInt = fn
    }

    func record(type: SdkEventType, latencyMs: Int? = nil) {
        guard enabled else { return }
        let bucket = buckets[type] ?? Bucket()
        bucket.count += 1
        if let latency = latencyMs {
            let cap = Constants.telemetryLatencySampleCap
            if bucket.latencies.count < cap {
                bucket.latencies.append(latency)
            } else {
                let idx = randomInt(bucket.count)
                if idx < cap {
                    bucket.latencies[idx] = latency
                }
            }
        }
        buckets[type] = bucket
        totalRecorded += 1
    }

    func start() {
        if flushTask != nil { return }
        let intervalMs = flushIntervalMs
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                let ns = UInt64(intervalMs) * 1_000_000
                try? await Task.sleep(nanoseconds: ns)
                if Task.isCancelled { break }
                try? await self?.flush()
            }
        }
    }

    func stop() {
        flushTask?.cancel()
        flushTask = nil
    }

    func flush() async throws {
        if buckets.isEmpty { return }
        let snapshot = Array(buckets)
        buckets.removeAll()
        totalRecorded = 0

        let dtos: [TelemetryEventDto] = snapshot.map { (type, bucket) in
            let sorted = bucket.latencies.sorted()
            return TelemetryEventDto(
                type: type.wire,
                count: bucket.count,
                p50: Self.percentile(sorted, 0.5),
                p95: Self.percentile(sorted, 0.95),
                p99: Self.percentile(sorted, 0.99)
            )
        }
        let payload = TelemetryPayloadDto(
            sdk: SdkInfoDto(platform: Constants.sdkPlatform, version: Constants.sdkVersion),
            nonce: Self.nonceHex(),
            events: dtos
        )
        let body = try adPlugaJsonEncoder.encode(payload)
        do {
            try await transport.postTelemetry(body: body)
        } catch {
            AdPlugaLogger.debug("telemetry post failed", error: error)
        }
    }

    private static func percentile(_ sorted: [Int], _ p: Double) -> Int? {
        if sorted.isEmpty { return nil }
        let raw = Int((p * Double(sorted.count)).rounded(.down))
        let idx = min(sorted.count - 1, raw)
        return sorted[idx]
    }

    private static func nonceHex() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, 16, &bytes)
        if status != errSecSuccess {
            for i in 0..<bytes.count { bytes[i] = UInt8.random(in: 0...255) }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
