import Foundation

enum Constants {
    static let sdkPlatform = "ios"
    static let sdkVersion = "0.2.0"
    static let defaultEndpoint = "https://edge.adpluga.com"

    static let viewabilityThreshold: Double = 0.5
    static let viewabilityDurationMs: Int = 1_000
    static let viewabilityTickMs: Int = 200

    static let telemetryFlushIntervalMs: Int = 300_000
    static let telemetryLatencySampleCap: Int = 128
    static let telemetryMaxEventsPerBatch: Int = 256

    static let featuresRevalidateMs: Int = 300_000
    static let featuresMinIntervalMs: Int = 30_000

    static let networkServeTimeoutMs: Int = 3_000
    static let networkTrackTimeoutMs: Int = 5_000
    static let networkRetryMaxAttempts: Int = 2
    static let networkRetryBaseBackoffMs: Int = 200

    static let keyHeader = "X-AdPluga-Key"
    static let platformHeader = "X-Adpluga-Sdk-Platform"
    static let versionHeader = "X-Adpluga-Sdk-Version"
    static let upgradeHeader = "X-Adpluga-Min-Sdk"

    static let keyPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(pattern: #"^pk_(live|test)_[A-Za-z0-9_-]{8,}$"#)
    }()
}
