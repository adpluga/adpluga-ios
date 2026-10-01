import Foundation

protocol TCFStorage {
    func gdprApplies() -> Bool?
    func tcString() -> String?
}

struct UserDefaultsTCFStorage: TCFStorage {
    static let gdprAppliesKey = "IABTCF_gdprApplies"
    static let tcStringKey = "IABTCF_TCString"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func gdprApplies() -> Bool? {
        switch defaults.object(forKey: Self.gdprAppliesKey) {
        case let number as NSNumber:
            switch number.intValue {
            case 1: return true
            case 0: return false
            default: return nil
            }
        case let string as String:
            switch string.trimmingCharacters(in: .whitespacesAndNewlines) {
            case "1": return true
            case "0": return false
            default: return nil
            }
        default:
            return nil
        }
    }

    func tcString() -> String? {
        defaults.string(forKey: Self.tcStringKey)
    }
}

struct TCFSignals: Equatable {
    var gdprApplies: Bool?
    var tcString: String?

    static func resolve(state: ConsentState, storage: TCFStorage) -> TCFSignals {
        TCFSignals(
            gdprApplies: state.gdpr ? true : storage.gdprApplies(),
            tcString: nonBlank(state.tcfString) ?? nonBlank(storage.tcString())
        )
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
