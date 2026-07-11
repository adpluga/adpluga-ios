import Foundation

public enum AdKind: String, Sendable, Equatable {
    case image
    case html
    case native
    case template
    case video
    case videoRewarded = "video_rewarded"

    public var wire: String { rawValue }

    public static func fromWire(_ raw: String) -> AdKind? {
        AdKind(rawValue: raw)
    }
}

public enum AdSource: String, Sendable, Equatable {
    case pool
    case direto
    case house
    case deal
    case mediation
    case test

    public var wire: String { rawValue }

    public static func fromWire(_ raw: String) -> AdSource {
        AdSource(rawValue: raw) ?? .house
    }
}

public struct Ad: Sendable, Equatable {
    public let id: String
    public let kind: AdKind
    public let source: AdSource
    public let assetUrl: String?
    public let html: String?
    public let nativeAssets: [String: String]?
    public let width: Int?
    public let height: Int?
    public let durationMs: Int?
    public let skippableAfterMs: Int?
    public let rewardAmount: Int?
    public let rewardCurrency: String
    public let format: String?
    public let advertiserName: String?
}

public struct ServeResponse: Sendable, Equatable {
    public let slotId: String
    public let ad: Ad
    public let impressionUrl: String?
    public let clickUrl: String?
    public let impressionToken: String
    public let clickToken: String?
    public let ttlMs: Int?
    public let quartilePings: [String: String]?
}
