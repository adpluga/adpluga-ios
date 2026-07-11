import Foundation

struct AdDto: Codable {
    let id: String
    let kind: String
    let source: String?
    let assetUrl: String?
    let html: String?
    let nativeAssets: [String: String]?
    let width: Int?
    let height: Int?
    let durationMs: Int?
    let skippableAfterMs: Int?
    let rewardAmount: Int?
    let rewardCurrency: String?
    let format: String?
    let advertiserName: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, source, html, width, height, format
        case assetUrl = "asset_url"
        case nativeAssets = "native_assets"
        case durationMs = "duration_ms"
        case skippableAfterMs = "skippable_after_ms"
        case rewardAmount = "reward_amount"
        case rewardCurrency = "reward_currency"
        case advertiserName = "advertiser_name"
    }

    func toModel(defaultSource: AdSource) -> Ad {
        Ad(
            id: id,
            kind: AdKind.fromWire(kind) ?? .image,
            source: source.map { AdSource.fromWire($0) } ?? defaultSource,
            assetUrl: assetUrl,
            html: html,
            nativeAssets: nativeAssets,
            width: width,
            height: height,
            durationMs: durationMs,
            skippableAfterMs: skippableAfterMs,
            rewardAmount: rewardAmount,
            rewardCurrency: rewardCurrency ?? "COIN",
            format: format,
            advertiserName: advertiserName
        )
    }
}

struct ServeResponseDto: Codable {
    let slotId: String
    let ad: AdDto
    let impressionUrl: String?
    let clickUrl: String?
    let impressionToken: String
    let clickToken: String?
    let ttlMs: Int?
    let quartilePings: [String: String]?

    enum CodingKeys: String, CodingKey {
        case ad
        case slotId = "slot_id"
        case impressionUrl = "impression_url"
        case clickUrl = "click_url"
        case impressionToken = "impression_token"
        case clickToken = "click_token"
        case ttlMs = "ttl_ms"
        case quartilePings = "quartile_pings"
    }

    func toModel() -> ServeResponse {
        ServeResponse(
            slotId: slotId,
            ad: ad.toModel(defaultSource: .house),
            impressionUrl: impressionUrl,
            clickUrl: clickUrl,
            impressionToken: impressionToken,
            clickToken: clickToken,
            ttlMs: ttlMs,
            quartilePings: quartilePings
        )
    }
}

struct FeaturesDto: Codable {
    let flags: [String: Bool]?
    let etag: String?
}

struct SdkInfoDto: Codable {
    let platform: String
    let version: String
}

struct TelemetryEventDto: Codable {
    let type: String
    let count: Int
    let p50: Int?
    let p95: Int?
    let p99: Int?
}

struct TelemetryPayloadDto: Codable {
    let sdk: SdkInfoDto
    let nonce: String
    let events: [TelemetryEventDto]
}

let adPlugaJsonDecoder: JSONDecoder = {
    let dec = JSONDecoder()
    return dec
}()

let adPlugaJsonEncoder: JSONEncoder = {
    let enc = JSONEncoder()
    enc.outputFormatting = []
    return enc
}()
