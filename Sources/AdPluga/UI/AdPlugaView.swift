#if canImport(UIKit)
import UIKit
import WebKit

public protocol AdPlugaViewDelegate: AnyObject {
    func adPlugaView(_ view: AdPlugaView, didLoad ad: Ad)
    func adPlugaView(_ view: AdPlugaView, didFailWith error: Error)
    func adPlugaViewDidRecordImpression(_ view: AdPlugaView)
    func adPlugaViewDidClick(_ view: AdPlugaView)
}

public extension AdPlugaViewDelegate {
    func adPlugaView(_ view: AdPlugaView, didLoad ad: Ad) {}
    func adPlugaView(_ view: AdPlugaView, didFailWith error: Error) {}
    func adPlugaViewDidRecordImpression(_ view: AdPlugaView) {}
    func adPlugaViewDidClick(_ view: AdPlugaView) {}
}

public final class AdPlugaView: UIView {
    public weak var delegate: AdPlugaViewDelegate?

    /// Set by an adapter that runs this view inside another SDK's waterfall
    /// (AdMob, AppLovin MAX, LevelPlay). The host owns refresh and retry, so
    /// the view never rotates or retries by itself, and the house fallback is
    /// reported as `AdPlugaError.noFill` instead of drawn, letting the next
    /// network fill the slot.
    public var mediated = false

    private var currentAd: Ad?
    private var currentResponse: ServeResponse?
    private var currentSlotId: String?
    private var loadTask: Task<Void, Never>?
    private var viewabilityHandle: Int?
    private var impressionFired = false
    private var htmlView: AdPlugaHtmlView?
    private var htmlProxy: _HtmlClickProxy?
    private var videoView: AdPlugaVideoView?
    private var videoProxy: _VideoDelegateProxy?
    private var carouselView: AdPlugaCarouselView?
    private var lastDeckSwipeAt: Date?
    private var fillFailures = 0
    private var testBadge: UIView?
    private var refreshTimer: Timer?
    private var refreshSeq: Int = 0
    private var currentFormat: String?
    private var foreground = true

    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false
        return view
    }()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupSubviews()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupSubviews()
    }

    private func setupSubviews() {
        backgroundColor = .clear
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
        isUserInteractionEnabled = true
    }

    public func load(slotId: String, format: String? = nil) {
        cancelInternal()
        currentSlotId = slotId
        currentFormat = format
        refreshSeq = 0
        fillFailures = 0
        observeLifecycle()
        reload()
    }

    /// Re-runs the current slot request, carrying the rotation index.
    private func reload() {
        guard let pluga = AdPluga.maybeInstance else {
            delegate?.adPlugaView(self, didFailWith: AdPlugaError.notInitialized)
            return
        }
        guard let slot = currentSlotId else { return }
        let format = currentFormat
        loadTask = Task { [weak self] in
            guard let self = self else { return }
            let response = await pluga.serve(slotId: slot, format: format, refreshSeq: self.refreshSeq)
            guard let response = response else {
                await MainActor.run {
                    self.delegate?.adPlugaView(self, didFailWith: AdPlugaError.network(statusCode: -1, detail: "no fill"))
                    self.scheduleRetry(pluga)
                }
                return
            }
            if await MainActor.run(body: { self.mediated }) && response.ad.source == .house {
                await MainActor.run { self.delegate?.adPlugaView(self, didFailWith: AdPlugaError.noFill) }
                return
            }
            await MainActor.run { self.fillFailures = 0 }
            let ad = response.ad
            switch ad.kind {
            case .image, .template:
                let image: UIImage?
                if let raw = ad.assetUrl, let url = URL(string: raw) {
                    image = await Self.loadImage(from: url)
                } else {
                    image = nil
                }
                await MainActor.run {
                    if let image = image {
                        self.teardownHtml()
                        self.teardownCarousel()
                        self.imageView.image = image
                        self.imageView.isAccessibilityElement = true
                        self.imageView.accessibilityLabel = adLabel(response.ad)
                        self.imageView.isHidden = false
                        self.currentAd = ad
                        self.currentResponse = response
                        self.updateTestBadge(ad)
                        self.delegate?.adPlugaView(self, didLoad: ad)
                        self.attachViewability(slotId: slot, response: response, pluga: pluga)
                        self.scheduleRefresh(response)
                    } else {
                        self.delegate?.adPlugaView(self, didFailWith: AdPlugaError.network(statusCode: -1, detail: "asset load failed"))
                    }
                }
            case .html:
                await MainActor.run {
                    self.currentAd = ad
                    self.currentResponse = response
                    self.imageView.isHidden = true
                    self.renderHtml(ad: ad, slotId: slot, response: response, pluga: pluga)
                    self.updateTestBadge(ad)
                    self.delegate?.adPlugaView(self, didLoad: ad)
                    self.attachViewability(slotId: slot, response: response, pluga: pluga)
                    self.scheduleRefresh(response)
                }
            case .carousel:
                var images: [UIImage?] = []
                for slide in ad.slides {
                    if let url = URL(string: slide.assetUrl) {
                        images.append(await Self.loadImage(from: url))
                    } else {
                        images.append(nil)
                    }
                }
                await MainActor.run {
                    self.currentAd = ad
                    self.currentResponse = response
                    self.imageView.isHidden = true
                    self.renderCarousel(ad: ad, slotId: slot, response: response, pluga: pluga, images: images)
                    self.updateTestBadge(ad)
                    self.delegate?.adPlugaView(self, didLoad: ad)
                    self.attachViewability(slotId: slot, response: response, pluga: pluga)
                    self.scheduleRefresh(response)
                }
            case .video, .videoRewarded, .audio:
                await MainActor.run {
                    self.currentAd = ad
                    self.currentResponse = response
                    self.imageView.isHidden = true
                    self.renderVideo(ad: ad, slotId: slot, response: response, pluga: pluga)
                    self.updateTestBadge(ad)
                    self.delegate?.adPlugaView(self, didLoad: ad)
                    self.attachViewability(slotId: slot, response: response, pluga: pluga)
                    self.scheduleRefresh(response)
                }
            default:
                await MainActor.run {
                    self.delegate?.adPlugaView(self, didFailWith: AdPlugaError.unsupportedFormat(ad.kind.wire))
                    self.scheduleRetry(pluga)
                }
            }
        }
    }

    @MainActor
    private func renderHtml(ad: Ad, slotId: String, response: ServeResponse, pluga: AdPluga) {
        teardownCarousel()
        let view = htmlView ?? {
            let view = AdPlugaHtmlView(frame: .zero)
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: topAnchor),
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            htmlView = view
            return view
        }()
        let proxy = _HtmlClickProxy { [weak self, weak pluga] in
            guard let self = self, let pluga = pluga else { return }
            pluga.fireClick(slotId: slotId, ad: ad, url: response.clickUrl, token: response.clickToken)
            self.delegate?.adPlugaViewDidClick(self)
        }
        htmlProxy = proxy
        view.delegate = proxy
        let assetUrl = ad.assetUrl.flatMap { URL(string: $0) }
        view.load(html: ad.html, assetUrl: assetUrl)
    }

    @MainActor
    private func teardownHtml() {
        htmlView?.stop()
        htmlView?.removeFromSuperview()
        htmlView = nil
        htmlProxy = nil
    }

    @MainActor
    private func renderCarousel(
        ad: Ad,
        slotId: String,
        response: ServeResponse,
        pluga: AdPluga,
        images: [UIImage?]
    ) {
        teardownHtml()
        teardownVideo()
        teardownCarousel()
        let view = AdPlugaCarouselView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        view.onClick = { [weak self] in
            guard let self = self else { return }
            pluga.fireClick(slotId: slotId, ad: ad, url: response.clickUrl, token: response.clickToken)
            self.delegate?.adPlugaViewDidClick(self)
        }
        view.onSwipe = { [weak self] in self?.lastDeckSwipeAt = Date() }
        view.bind(slides: ad.slides, images: images, fallbackLabel: adLabel(ad))
        carouselView = view
    }

    @MainActor
    private func teardownCarousel() {
        carouselView?.teardown()
        carouselView?.removeFromSuperview()
        carouselView = nil
        lastDeckSwipeAt = nil
    }

    @MainActor
    private func renderVideo(ad: Ad, slotId: String, response: ServeResponse, pluga: AdPluga) {
        teardownHtml()
        teardownCarousel()
        let view = videoView ?? {
            let view = AdPlugaVideoView(frame: .zero)
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: topAnchor),
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            videoView = view
            return view
        }()
        let proxy = _VideoDelegateProxy(onClick: { [weak self, weak pluga] in
            guard let self = self, let pluga = pluga else { return }
            pluga.fireClick(slotId: slotId, ad: ad, url: response.clickUrl, token: response.clickToken)
            self.delegate?.adPlugaViewDidClick(self)
        })
        videoProxy = proxy
        view.delegate = proxy
        view.clickThroughUrl = response.clickUrl.flatMap { URL(string: $0) }
        view.openClickExternally = true
        let url = ad.assetUrl.flatMap { URL(string: $0) }
        view.load(videoUrl: url, quartilePings: response.quartilePings)
    }

    @MainActor
    private func teardownVideo() {
        videoView?.teardown()
        videoView?.removeFromSuperview()
        videoView = nil
        videoProxy = nil
    }

    @MainActor
    private func updateTestBadge(_ ad: Ad) {
        testBadge?.removeFromSuperview()
        testBadge = nil
        guard ad.isTest else { return }
        testBadge = TestBadge.attach(to: self)
    }

    private static func loadImage(from url: URL) async -> UIImage? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    private func attachViewability(slotId: String, response: ServeResponse, pluga: AdPluga) {
        viewabilityHandle = ViewabilityTracker.shared.register(view: self) { [weak self, weak pluga] in
            guard let self = self, let pluga = pluga, !self.impressionFired, let ad = self.currentAd else { return }
            self.impressionFired = true
            pluga.fireImpression(slotId: slotId, ad: ad, url: response.impressionUrl, token: response.impressionToken)
            pluga.fireViewable(slotId: slotId, ad: ad, token: response.impressionToken)
            self.delegate?.adPlugaViewDidRecordImpression(self)
        }
    }

    @objc private func handleTap() {
        guard let ad = currentAd, let response = currentResponse, let pluga = AdPluga.maybeInstance else { return }
        if ad.kind == .html || ad.kind == .video || ad.kind == .carousel { return }
        pluga.fireClick(slotId: currentSlotId ?? "", ad: ad, url: response.clickUrl, token: response.clickToken)
        openClickThrough(response.clickUrl)
        delegate?.adPlugaViewDidClick(self)
    }

    /// Sends the user to the advertiser. The signed click endpoint redirects to
    /// the destination, which is why the URL is never read from the creative.
    /// HTML and video creatives have always navigated; image ones reported the
    /// click and went nowhere, so the advertiser paid for a tap that never
    /// arrived.
    private func openClickThrough(_ raw: String?) {
        guard let raw, let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    public override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil {
            cancelInternal()
        }
    }

    /// Arms the next rotation for the cadence the server published for this
    /// slot. Nothing is scheduled when the slot has no cadence, when the app is
    /// backgrounded, or when the value is below the industry floor.
    @MainActor
    private func scheduleRefresh(_ response: ServeResponse) {
        cancelRefresh()
        guard foreground, !mediated else { return }
        let secs = response.refreshAfterSeconds
        guard secs > 0 else { return }
        let floor = response.ad.isTest ? Constants.minRefreshSecondsTest : Constants.minRefreshSeconds
        let interval = TimeInterval(max(secs, floor))
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.onRefreshTick() }
        }
        refreshTimer = timer
    }

    /// Arms another attempt after a failed fill, backing off exponentially from
    /// the client's cadence floor. Independent of the slot's rotation cadence:
    /// rotation is off by default, so a slot that relied on it would stay blank
    /// for the rest of the session after a single miss.
    @MainActor
    private func scheduleRetry(_ pluga: AdPluga) {
        cancelRefresh()
        guard foreground, !mediated else { return }
        let base = pluga.isTestKey ? Constants.minRefreshSecondsTest : Constants.minRefreshSeconds
        let secs = min(base << min(fillFailures, 10), Constants.fillRetryMaxBackoffSeconds)
        fillFailures += 1
        AdPlugaLogger.warn("slot \(currentSlotId ?? "") unfilled; retrying in \(secs)s")
        let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(secs), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        refreshTimer = timer
    }

    @MainActor
    private func cancelRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    @MainActor
    private func onRefreshTick() {
        refreshTimer = nil
        guard let response = currentResponse else { return }
        // Rotating an off-screen ad would spend a decision on an impression the
        // MRC guidelines classify as non-viewable: wait for it to come back
        // into view instead, re-arming on the same cadence.
        guard ViewabilityTracker.shared.isVisible(self) else {
            scheduleRefresh(response)
            return
        }
        // A deck the reader is still swiping through keeps the slot; rotation
        // resumes one full cadence after the last swipe.
        let secs = response.refreshAfterSeconds
        if let last = lastDeckSwipeAt, secs > 0,
           Date().timeIntervalSince(last) < TimeInterval(secs) {
            scheduleRefresh(response)
            return
        }
        refreshSeq += 1
        reload()
    }

    private func observeLifecycle() {
        let center = NotificationCenter.default
        center.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
        center.addObserver(self, selector: #selector(appDidBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(appWillForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    @objc private func appDidBackground() {
        foreground = false
        Task { @MainActor in self.cancelRefresh() }
    }

    @objc private func appWillForeground() {
        foreground = true
        Task { @MainActor in
            guard let response = self.currentResponse else { return }
            self.scheduleRefresh(response)
        }
    }

    private func cancelInternal() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        loadTask?.cancel()
        loadTask = nil
        if let handle = viewabilityHandle {
            ViewabilityTracker.shared.unregister(handle: handle)
        }
        viewabilityHandle = nil
        impressionFired = false
    }

    deinit {
        refreshTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        let handle = viewabilityHandle
        if let handle = handle {
            Task { @MainActor in
                ViewabilityTracker.shared.unregister(handle: handle)
            }
        }
    }
}

final class _HtmlClickProxy: NSObject, AdPlugaHtmlViewDelegate {
    let onClick: () -> Void
    init(onClick: @escaping () -> Void) { self.onClick = onClick }
    func adPlugaHtmlViewDidClick(_ view: AdPlugaHtmlView) { onClick() }
}

final class _VideoDelegateProxy: NSObject, AdPlugaVideoViewDelegate {
    let onClick: () -> Void
    var onProgress: ((Int, Int) -> Void)?
    var onComplete: (() -> Void)?
    init(onClick: @escaping () -> Void) { self.onClick = onClick }
    func adPlugaVideoViewDidClick(_ view: AdPlugaVideoView) { onClick() }
    func adPlugaVideoView(_ view: AdPlugaVideoView, didUpdatePosition positionMs: Int, durationMs: Int) {
        onProgress?(positionMs, durationMs)
    }
    func adPlugaVideoViewDidComplete(_ view: AdPlugaVideoView) { onComplete?() }
}
#endif
