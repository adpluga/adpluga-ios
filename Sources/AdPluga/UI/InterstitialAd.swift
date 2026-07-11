#if canImport(UIKit)
import UIKit
import WebKit

public final class InterstitialAd {
    public let ad: Ad
    private let slotId: String
    private let response: ServeResponse
    private var impressionFired = false

    fileprivate init(slotId: String, response: ServeResponse) {
        self.slotId = slotId
        self.response = response
        self.ad = response.ad
    }

    public static func load(slotId: String, format: String? = nil) async throws -> InterstitialAd {
        guard let pluga = AdPluga.maybeInstance else { throw AdPlugaError.notInitialized }
        guard let response = await pluga.serve(slotId: slotId, format: format) else {
            throw AdPlugaError.network(statusCode: -1, detail: "no fill")
        }
        switch response.ad.kind {
        case .image, .template, .html, .video:
            return InterstitialAd(slotId: slotId, response: response)
        default:
            throw AdPlugaError.unsupportedFormat(response.ad.kind.wire)
        }
    }

    @MainActor
    public func show(from presenter: UIViewController, onDismiss: (() -> Void)? = nil) async {
        guard let pluga = AdPluga.maybeInstance else { return }
        let controller: InterstitialViewController
        if ad.kind == .html {
            controller = InterstitialViewController(
                html: ad.html,
                assetUrl: ad.assetUrl.flatMap { URL(string: $0) },
                image: nil,
                videoUrl: nil,
                quartilePings: nil,
                clickThroughUrl: nil,
                onClick: { [weak self, weak pluga] in
                    guard let self = self, let pluga = pluga else { return }
                    pluga.fireClick(slotId: self.slotId, ad: self.ad, url: self.response.clickUrl, token: self.response.clickToken)
                },
                onDismiss: { onDismiss?() }
            )
        } else if ad.kind == .video {
            let videoUrl = ad.assetUrl.flatMap { URL(string: $0) }
            controller = InterstitialViewController(
                html: nil,
                assetUrl: nil,
                image: nil,
                videoUrl: videoUrl,
                quartilePings: response.quartilePings,
                clickThroughUrl: response.clickUrl.flatMap { URL(string: $0) },
                onClick: { [weak self, weak pluga] in
                    guard let self = self, let pluga = pluga else { return }
                    pluga.fireClick(slotId: self.slotId, ad: self.ad, url: self.response.clickUrl, token: self.response.clickToken)
                },
                onDismiss: { onDismiss?() }
            )
        } else {
            guard let raw = ad.assetUrl, let url = URL(string: raw), let image = await Self.loadImage(url) else {
                onDismiss?()
                return
            }
            controller = InterstitialViewController(
                html: nil,
                assetUrl: nil,
                image: image,
                videoUrl: nil,
                quartilePings: nil,
                clickThroughUrl: nil,
                onClick: { [weak self, weak pluga] in
                    guard let self = self, let pluga = pluga else { return }
                    pluga.fireClick(slotId: self.slotId, ad: self.ad, url: self.response.clickUrl, token: self.response.clickToken)
                },
                onDismiss: { onDismiss?() }
            )
        }
        controller.modalPresentationStyle = .fullScreen
        controller.onShow = { [weak self, weak pluga] in
            guard let self = self, let pluga = pluga, !self.impressionFired else { return }
            self.impressionFired = true
            pluga.fireImpression(slotId: self.slotId, ad: self.ad, url: self.response.impressionUrl, token: self.response.impressionToken)
        }
        presenter.present(controller, animated: true)
    }

    private static func loadImage(_ url: URL) async -> UIImage? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}

final class InterstitialViewController: UIViewController, AdPlugaHtmlViewDelegate, AdPlugaVideoViewDelegate {
    private let html: String?
    private let assetUrl: URL?
    private let image: UIImage?
    private let videoUrl: URL?
    private let quartilePings: [String: String]?
    private let clickThroughUrl: URL?
    private let onClick: () -> Void
    private let onDismiss: () -> Void
    var onShow: (() -> Void)?

    init(
        html: String?,
        assetUrl: URL?,
        image: UIImage?,
        videoUrl: URL?,
        quartilePings: [String: String]?,
        clickThroughUrl: URL?,
        onClick: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.html = html
        self.assetUrl = assetUrl
        self.image = image
        self.videoUrl = videoUrl
        self.quartilePings = quartilePings
        self.clickThroughUrl = clickThroughUrl
        self.onClick = onClick
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        if let videoUrl = videoUrl {
            let video = AdPlugaVideoView(frame: .zero)
            video.translatesAutoresizingMaskIntoConstraints = false
            video.delegate = self
            video.clickThroughUrl = clickThroughUrl
            video.openClickExternally = true
            view.addSubview(video)
            NSLayoutConstraint.activate([
                video.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                video.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                video.topAnchor.constraint(equalTo: view.topAnchor),
                video.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
            video.load(videoUrl: videoUrl, quartilePings: quartilePings)
        } else if let image = image {
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFit
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.isUserInteractionEnabled = true
            view.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                imageView.topAnchor.constraint(equalTo: view.topAnchor),
                imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            imageView.addGestureRecognizer(tap)
        } else {
            let html = AdPlugaHtmlView(frame: .zero)
            html.translatesAutoresizingMaskIntoConstraints = false
            html.delegate = self
            view.addSubview(html)
            NSLayoutConstraint.activate([
                html.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                html.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                html.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                html.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            ])
            html.load(html: self.html, assetUrl: assetUrl)
        }

        let closeBtn = UIButton(type: .system)
        closeBtn.setTitle("\u{00D7}", for: .normal)
        closeBtn.setTitleColor(.white, for: .normal)
        closeBtn.titleLabel?.font = .systemFont(ofSize: 32, weight: .bold)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.addTarget(self, action: #selector(handleClose), for: .touchUpInside)
        view.addSubview(closeBtn)
        NSLayoutConstraint.activate([
            closeBtn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeBtn.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            closeBtn.widthAnchor.constraint(equalToConstant: 44),
            closeBtn.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onShow?()
    }

    @objc private func handleTap() { onClick() }

    @objc private func handleClose() {
        dismiss(animated: true) { [weak self] in
            self?.onDismiss()
        }
    }

    func adPlugaHtmlViewDidClick(_ view: AdPlugaHtmlView) { onClick() }
    func adPlugaVideoViewDidClick(_ view: AdPlugaVideoView) { onClick() }
}
#endif
