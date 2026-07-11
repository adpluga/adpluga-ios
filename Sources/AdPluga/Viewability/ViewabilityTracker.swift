#if canImport(UIKit)
import UIKit

@MainActor
final class ViewabilityTracker {
    static let shared = ViewabilityTracker()

    private struct Slot {
        weak var view: UIView?
        let onFire: () -> Void
        var dwellMs: Int
        var fired: Bool
    }

    private var slots: [Int: Slot] = [:]
    private var nextHandle: Int = 1
    private var timer: Timer?
    private let tickMs: Int = Constants.viewabilityTickMs
    private let durationMs: Int = Constants.viewabilityDurationMs
    private let threshold: Double = Constants.viewabilityThreshold

    private init() {}

    @discardableResult
    func register(view: UIView, onFire: @escaping () -> Void) -> Int {
        let handle = nextHandle
        nextHandle += 1
        slots[handle] = Slot(view: view, onFire: onFire, dwellMs: 0, fired: false)
        ensureTicking()
        return handle
    }

    func unregister(handle: Int) {
        slots.removeValue(forKey: handle)
        if slots.isEmpty { stopTicking() }
    }

    private func ensureTicking() {
        if timer != nil { return }
        let interval = TimeInterval(tickMs) / 1000.0
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func stopTicking() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        var toRemove: [Int] = []
        for (handle, var slot) in slots {
            guard let view = slot.view, view.window != nil, !view.isHidden, view.alpha > 0 else {
                toRemove.append(handle)
                continue
            }
            let ratio = visibleRatio(of: view)
            if ratio >= threshold {
                slot.dwellMs += tickMs
                if slot.dwellMs >= durationMs && !slot.fired {
                    slot.fired = true
                    slots[handle] = slot
                    slot.onFire()
                    toRemove.append(handle)
                    continue
                }
            } else {
                slot.dwellMs = 0
            }
            slots[handle] = slot
        }
        for handle in toRemove {
            slots.removeValue(forKey: handle)
        }
        if slots.isEmpty {
            stopTicking()
        }
    }

    private func visibleRatio(of view: UIView) -> Double {
        guard let window = view.window else { return 0 }
        let inWindow = view.convert(view.bounds, to: nil)
        let intersection = inWindow.intersection(window.bounds)
        if intersection.isNull || intersection.isEmpty { return 0 }
        let viewArea = view.bounds.width * view.bounds.height
        if viewArea <= 0 { return 0 }
        let visibleArea = intersection.width * intersection.height
        return Double(visibleArea) / Double(viewArea)
    }
}
#endif
