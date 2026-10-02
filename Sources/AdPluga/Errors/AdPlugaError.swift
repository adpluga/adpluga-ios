import Foundation

public enum AdPlugaError: Error, LocalizedError, Equatable {
    case notInitialized
    case invalidKey(String)
    /// `initialize` was called with a different publisher key than the live
    /// instance holds. Rotating a key revokes the previous one immediately, so
    /// returning the old instance would leave the app serving with a revoked
    /// key. Call `destroy()` first to re-initialize deliberately.
    case alreadyInitialized(activeKey: String, requestedKey: String)
    case network(statusCode: Int, detail: String?)
    case upgradeRequired(minVersion: String?)
    case consentDenied
    case unsupportedFormat(String)
    /// Nothing paid to show. Raised instead of drawing the house fallback when
    /// the slot runs inside another SDK's waterfall, so the next network can
    /// still fill it.
    case noFill

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "AdPluga.initialize must be called before using the SDK."
        case .invalidKey(let key):
            return "Invalid publishable key: \(key)"
        case .alreadyInitialized:
            return "AdPluga is already initialized with a different publisher key; call destroy() before initializing again."
        case .network(let status, let detail):
            return "Network error status=\(status) detail=\(detail ?? "")"
        case .upgradeRequired(let minVersion):
            return "SDK upgrade required. min=\(minVersion ?? "unknown")"
        case .consentDenied:
            return "Consent denied."
        case .unsupportedFormat(let kind):
            return "Unsupported ad format: \(kind)"
        case .noFill:
            return "No paid ad for this slot."
        }
    }
}
