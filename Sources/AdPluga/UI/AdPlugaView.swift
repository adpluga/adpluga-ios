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

    private var currentAd: Ad?
    private var currentResponse: ServeResponse?
    private var loadTask: Task<Void, Never>?
    private var viewabilityHandle: Int?
    private var impressionFired = false
    private var htmlView: AdPlugaHtmlView?
    private var htmlProxy: _HtmlClickProxy?
    private var videoView: AdPlugaVideoView?
    private var videoProxy: _VideoDelegateProxy?

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
        guard let pluga = AdPluga.maybeInstance else {
            delegate?.adPlugaView(self, didFailWith: AdPlugaError.notInitialized)
            return
        }
        let slot = slotId
        loadTask = Task { [weak self] in
            guard let self = self else { return }
            let response = await pluga.serve(slotId: slot, format: format)
            guard let response = response else {
                await MainActor.run {
                    self.delegate?.adPlugaView(self, didFailWith: AdPlugaError.network(statusCode: -1, detail: "no fill"))
                }
                return
            }
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
                        self.imageView.image = image
                        self.imageView.isHidden = false
                        self.currentAd = ad
                        self.currentResponse = response
                        self.delegate?.adPlugaView(self, didLoad: ad)
                        self.attachViewability(slotId: slot, response: response, pluga: pluga)
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
                    self.delegate?.adPlugaView(self, didLoad: ad)
                    self.attachViewability(slotId: slot, response: response, pluga: pluga)
                }
            case .video:
                await MainActor.run {
                    self.currentAd = ad
                    self.currentResponse = response
                    self.imageView.isHidden = true
                    self.renderVideo(ad: ad, slotId: slot, response: response, pluga: pluga)
                    self.delegate?.adPlugaView(self, didLoad: ad)
                    self.attachViewability(slotId: slot, response: response, pluga: pluga)
                }
            default:
                await MainActor.run {
                    self.delegate?.adPlugaView(self, didFailWith: AdPlugaError.unsupportedFormat(ad.kind.wire))
                }
            }
        }
    }

    @MainActor
    private func renderHtml(ad: Ad, slotId: String, response: ServeResponse, pluga: AdPluga) {
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
    private func renderVideo(ad: Ad, slotId: String, response: ServeResponse, pluga: AdPluga) {
        teardownHtml()
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
            self.delegate?.adPlugaViewDidRecordImpression(self)
        }
    }

    @objc private func handleTap() {
        guard let ad = currentAd, let response = currentResponse, let pluga = AdPluga.maybeInstance else { return }
        if ad.kind == .html || ad.kind == .video { return }
        pluga.fireClick(slotId: response.slotId, ad: ad, url: response.clickUrl, token: response.clickToken)
        delegate?.adPlugaViewDidClick(self)
    }

    public override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil {
            cancelInternal()
        }
    }

    private func cancelInternal() {
        loadTask?.cancel()
        loadTask = nil
        if let handle = viewabilityHandle {
            ViewabilityTracker.shared.unregister(handle: handle)
        }
        viewabilityHandle = nil
        impressionFired = false
    }

    deinit {
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
