import Foundation

/// What an AdPluga line item in another SDK's waterfall points at, read from
/// the parameter the publisher types into AdMob, MAX or LevelPlay.
///
/// Two shapes are accepted:
/// - `{"publisher_key":"pk_live_…","slot_id":"…"}` — the adapter initialises
///   AdPluga itself;
/// - a bare slot id — the app has already called `AdPluga.initialize`.
public struct MediationSlot: Equatable, Sendable {
    public let slotId: String
    public let publisherKey: String?

    public init(slotId: String, publisherKey: String? = nil) {
        self.slotId = slotId
        self.publisherKey = publisherKey
    }

    /// Parses the waterfall parameter; nil when it names no slot.
    public static func parse(_ raw: String?) -> MediationSlot? {
        let text = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard text.hasPrefix("{") else { return MediationSlot(slotId: text) }
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let slot = ((obj["slot_id"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slot.isEmpty else { return nil }
        let key = (obj["publisher_key"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return MediationSlot(slotId: slot, publisherKey: key?.isEmpty == false ? key : nil)
    }

    /// The same slot, keyed by `fallbackKey` when it carries none of its own.
    public func keyed(by fallbackKey: String?) -> MediationSlot {
        guard publisherKey == nil,
              let key = fallbackKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return self }
        return MediationSlot(slotId: slotId, publisherKey: key)
    }

    /// Returns the live instance, initialising it from `publisherKey` when needed.
    @discardableResult
    public func ensureInitialized() throws -> AdPluga {
        if let live = AdPluga.maybeInstance { return live }
        guard let key = publisherKey else { throw AdPlugaError.notInitialized }
        return try AdPluga.initialize(publisherKey: key)
    }
}
