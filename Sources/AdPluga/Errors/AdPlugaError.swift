import Foundation

public enum AdPlugaError: Error, LocalizedError, Equatable {
    case notInitialized
    case invalidKey(String)
    case network(statusCode: Int, detail: String?)
    case upgradeRequired(minVersion: String?)
    case consentDenied
    case unsupportedFormat(String)

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "AdPluga.initialize must be called before using the SDK."
        case .invalidKey(let key):
            return "Invalid publishable key: \(key)"
        case .network(let status, let detail):
            return "Network error status=\(status) detail=\(detail ?? "")"
        case .upgradeRequired(let minVersion):
            return "SDK upgrade required. min=\(minVersion ?? "unknown")"
        case .consentDenied:
            return "Consent denied."
        case .unsupportedFormat(let kind):
            return "Unsupported ad format: \(kind)"
        }
    }
}
