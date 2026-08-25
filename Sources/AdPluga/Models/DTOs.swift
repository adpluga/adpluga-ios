import Foundation

struct AdDto: Codable {
    let id: String
    let type: String
    let assetUrl: String?
    let html: String?
    let billingUrl: String?
    let title: String?
    let body: String?
    let ctaText: String?
    let sponsoredBy: String?
    let iconUrl: String?
    let mainImageUrl: String?
    let videoUrl: String?
    let audioUrl: String?
    let vastUrl: String?
    let width: Int?
    let height: Int?
    let durationMs: Int?
    let skippableAfterMs: Int?
    let rewardAmount: Int?
    let rewardCurrency: String?
    let format: String?
    let advertiserName: String?
    let test: Bool?

    enum CodingKeys: String, CodingKey {
        case id, type, html, title, body, width, height, format, test
        case assetUrl = "asset_url"
        case billingUrl = "billing_url"
        case ctaText = "cta_text"
        case sponsoredBy = "sponsored_by"
        case iconUrl = "icon_url"
        case mainImageUrl = "main_image_url"
        case videoUrl = "video_url"
        case audioUrl = "audio_url"
        case vastUrl = "vast_url"
        case durationMs = "duration_ms"
        case skippableAfterMs = "skippable_after_ms"
        case rewardAmount = "reward_amount"
        case rewardCurrency = "reward_currency"
        case advertiserName = "advertiser_name"
    }

    func toModel(source: AdSource) -> Ad {
        Ad(
            id: id,
            kind: AdKind.fromWire(type) ?? .image,
            source: source,
            assetUrl: assetUrl ?? videoUrl ?? audioUrl ?? vastUrl,
            html: html,
            billingUrl: billingUrl,
            nativeAssets: buildNativeAssets(),
            width: width,
            height: height,
            durationMs: durationMs,
            skippableAfterMs: skippableAfterMs,
            rewardAmount: rewardAmount,
            rewardCurrency: rewardCurrency ?? "COIN",
            format: format,
            advertiserName: advertiserName,
            isTest: test ?? false
        )
    }

    // Native assets arrive as flat top-level fields on the serve contract;
    // expose them as a map so integrators compose their own view.
    private func buildNativeAssets() -> [String: String]? {
        var m: [String: String] = [:]
        if let title { m["title"] = title }
        if let body { m["body"] = body }
        if let ctaText { m["cta_text"] = ctaText }
        if let sponsoredBy { m["sponsored_by"] = sponsoredBy }
        if let iconUrl { m["icon_url"] = iconUrl }
        if let mainImageUrl { m["main_image_url"] = mainImageUrl }
        return m.isEmpty ? nil : m
    }
}

struct ServeResponseDto: Codable {
    let ad: AdDto
    let impressionUrl: String?
    let clickUrl: String?
    let conversionUrl: String?
    let trackToken: String
    let conversionToken: String?
    let source: String?
    let quartilePings: [String: String]?

    enum CodingKeys: String, CodingKey {
        case ad, source
        case impressionUrl = "impression_url"
        case clickUrl = "click_url"
        case conversionUrl = "conversion_url"
        case trackToken = "track_token"
        case conversionToken = "conversion_token"
        case quartilePings = "quartile_pings"
    }

    func toModel() -> ServeResponse {
        let src = source.map { AdSource.fromWire($0) } ?? .house
        // One signed track_token covers impression/click/viewable; the event
        // is disambiguated by the endpoint / body. Both slots carry it.
        return ServeResponse(
            slotId: "",
            ad: ad.toModel(source: src),
            impressionUrl: impressionUrl,
            clickUrl: clickUrl,
            impressionToken: trackToken,
            clickToken: trackToken,
            ttlMs: nil,
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
