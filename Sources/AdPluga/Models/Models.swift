import Foundation

public enum AdKind: String, Sendable, Equatable {
    case image
    case html
    case native
    case template
    case video
    case videoRewarded = "video_rewarded"
    case audio
    case carousel

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

/// One card of a carousel. The whole deck shares the ad's click token and its
/// single impression, so swiping never mints or spends anything extra.
public struct Slide: Sendable, Equatable {
    public let assetUrl: String
    public let title: String?
    public let body: String?
    public let ctaText: String?

    public init(assetUrl: String, title: String? = nil, body: String? = nil, ctaText: String? = nil) {
        self.assetUrl = assetUrl
        self.title = title
        self.body = body
        self.ctaText = ctaText
    }
}

public struct Ad: Sendable, Equatable {
    public let id: String
    public let kind: AdKind
    public let source: AdSource
    public let assetUrl: String?
    public let html: String?
    public let billingUrl: String?
    public let nativeAssets: [String: String]?
    public let width: Int?
    public let height: Int?
    public let durationMs: Int?
    public let skippableAfterMs: Int?
    public let rewardAmount: Int?
    public let rewardCurrency: String
    public let format: String?
    public let advertiserName: String?

    /// Announced by VoiceOver in place of the creative. An ad is never
    /// decorative, so a view with nothing here falls back to the title rather
    /// than leaving the image unlabelled.
    public let altText: String?
    public let slides: [Slide]
    public let isTest: Bool

    /// A mediation bidder's own pixels, fired alongside our impression and
    /// click so the SSP counts (and pays for) what it served. Empty for
    /// first-party creatives.
    public let impressionTrackers: [String]
    public let clickTrackers: [String]
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
    /// Publisher-configured rotation cadence for this slot, in seconds.
    /// 0 means the slot must not rotate.
    public let refreshAfterSeconds: Int
}
