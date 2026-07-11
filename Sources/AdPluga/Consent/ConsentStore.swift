import Foundation

final class ConsentStore {
    typealias Listener = (ConsentState) -> Void

    private let lock = NSLock()
    private var _current: ConsentState
    private var listeners: [UUID: Listener] = [:]

    init(initial: ConsentState) {
        self._current = initial
    }

    var state: ConsentState {
        lock.lock()
        defer { lock.unlock() }
        return _current
    }

    @discardableResult
    func update(_ next: ConsentState) -> Bool {
        lock.lock()
        if _current == next {
            lock.unlock()
            return false
        }
        _current = next
        let snapshot = Array(listeners.values)
        lock.unlock()
        for fn in snapshot {
            fn(next)
        }
        return true
    }

    @discardableResult
    func addListener(_ fn: @escaping Listener) -> UUID {
        lock.lock()
        let id = UUID()
        listeners[id] = fn
        lock.unlock()
        return id
    }

    func removeListener(_ id: UUID) {
        lock.lock()
        listeners.removeValue(forKey: id)
        lock.unlock()
    }
}
