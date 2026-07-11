import Foundation

public enum SdkEvent: Sendable {
    case initCompleted(at: Date)
    case adServed(slotId: String, ad: Ad, at: Date)
    case adFailed(slotId: String, at: Date, message: String)
    case impression(slotId: String, adId: String, at: Date)
    case click(slotId: String, adId: String, at: Date)
    case consentChanged(state: ConsentState, at: Date)
    case featuresUpdated(view: FeaturesView, at: Date)
    case upgradeRequired(minVersion: String?, at: Date)
}
