import Foundation

public final class FeaturesView: @unchecked Sendable {
    private let flags: [String: Bool]

    init(flags: [String: Bool] = [:]) {
        self.flags = flags
    }

    public func flag(_ key: String, fallback: Bool = false) -> Bool {
        flags[key] ?? fallback
    }

    public func snapshot() -> [String: Bool] {
        flags
    }

    public static let empty = FeaturesView()
}
