import Foundation

public struct ConsentState: Equatable, Sendable {
    public var gdpr: Bool
    public var adPersonalization: Bool
    public var limitedTracking: Bool
    public var ccpaOptOut: Bool
    public var tcfString: String?

    public init(
        gdpr: Bool = false,
        adPersonalization: Bool = true,
        limitedTracking: Bool = false,
        ccpaOptOut: Bool = false,
        tcfString: String? = nil
    ) {
        self.gdpr = gdpr
        self.adPersonalization = adPersonalization
        self.limitedTracking = limitedTracking
        self.ccpaOptOut = ccpaOptOut
        self.tcfString = tcfString
    }

    public var isPersonalized: Bool {
        adPersonalization && !limitedTracking && !ccpaOptOut
    }

    public static let `default` = ConsentState()
}
