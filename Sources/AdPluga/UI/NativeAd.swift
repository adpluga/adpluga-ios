#if canImport(UIKit)
import UIKit

public final class NativeAd {
    public let ad: Ad
    private let slotId: String
    private let response: ServeResponse
    private var viewabilityHandle: Int?
    private var impressionFired = false
    private weak var attachedContainer: UIView?
    private var attachedGesture: AdPlugaTapGesture?

    fileprivate init(slotId: String, response: ServeResponse) {
        self.slotId = slotId
        self.response = response
        self.ad = response.ad
    }

    public static func load(slotId: String, format: String? = nil) async throws -> NativeAd {
        guard let pluga = AdPluga.maybeInstance else { throw AdPlugaError.notInitialized }
        guard let response = await pluga.serve(slotId: slotId, format: format) else {
            throw AdPlugaError.network(statusCode: -1, detail: "no fill")
        }
        return NativeAd(slotId: slotId, response: response)
    }

    @MainActor
    public func attach(to container: UIView, onClick: @escaping () -> Void) {
        guard let pluga = AdPluga.maybeInstance else { return }
        detachInternal()
        attachedContainer = container
        viewabilityHandle = ViewabilityTracker.shared.register(view: container) { [weak self, weak pluga] in
            guard let self = self, let pluga = pluga, !self.impressionFired else { return }
            self.impressionFired = true
            pluga.fireImpression(slotId: self.slotId, ad: self.ad, url: self.response.impressionUrl, token: self.response.impressionToken)
        }
        let gesture = AdPlugaTapGesture { [weak self, weak pluga] in
            guard let self = self, let pluga = pluga else { return }
            pluga.fireClick(slotId: self.slotId, ad: self.ad, url: self.response.clickUrl, token: self.response.clickToken)
            onClick()
        }
        attachedGesture = gesture
        container.isUserInteractionEnabled = true
        container.addGestureRecognizer(gesture)
    }

    @MainActor
    public func release() {
        detachInternal()
    }

    @MainActor
    private func detachInternal() {
        if let handle = viewabilityHandle {
            ViewabilityTracker.shared.unregister(handle: handle)
        }
        viewabilityHandle = nil
        if let container = attachedContainer, let gesture = attachedGesture {
            container.removeGestureRecognizer(gesture)
        }
        attachedGesture = nil
        attachedContainer = nil
    }
}

final class AdPlugaTapGesture: UITapGestureRecognizer {
    private let handler: () -> Void
    init(handler: @escaping () -> Void) {
        self.handler = handler
        super.init(target: nil, action: nil)
        addTarget(self, action: #selector(fire))
    }
    @objc private func fire() { handler() }
}
#endif
