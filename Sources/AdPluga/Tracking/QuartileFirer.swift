import Foundation

final class QuartileFirer: @unchecked Sendable {
    private let pings: [String: String]?
    private let session: URLSession
    private let lock = NSLock()
    private var fired: Set<String> = []

    init(pings: [String: String]?, session: URLSession = .shared) {
        self.pings = pings
        self.session = session
    }

    func update(positionMs: Int, durationMs: Int) {
        guard let pings = pings, !pings.isEmpty, durationMs > 0 else { return }
        for threshold in Self.thresholds {
            let target = Int(Double(durationMs) * threshold.ratio)
            if positionMs < target { continue }
            let alreadyFired: Bool = {
                lock.lock()
                defer { lock.unlock() }
                if fired.contains(threshold.key) { return true }
                fired.insert(threshold.key)
                return false
            }()
            if alreadyFired { continue }
            guard let raw = pings[threshold.key], !raw.isEmpty, let url = URL(string: raw) else {
                continue
            }
            fire(url)
        }
    }

    func reset() {
        lock.lock()
        fired.removeAll()
        lock.unlock()
    }

    private func fire(_ url: URL) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 3
        let task = session.dataTask(with: request) { _, _, _ in }
        task.resume()
    }

    private struct Threshold {
        let key: String
        let ratio: Double
    }

    private static let thresholds: [Threshold] = [
        Threshold(key: "start", ratio: 0.0),
        Threshold(key: "first_quartile", ratio: 0.25),
        Threshold(key: "midpoint", ratio: 0.5),
        Threshold(key: "third_quartile", ratio: 0.75),
        Threshold(key: "complete", ratio: 1.0),
    ]
}
