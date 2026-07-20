#if canImport(UIKit)
import UIKit

public typealias RewardCallback = (Int, String) -> Void

public final class RewardedAd {
    public let ad: Ad
    private let slotId: String
    private let response: ServeResponse
    private var impressionFired = false

    fileprivate init(slotId: String, response: ServeResponse) {
        self.slotId = slotId
        self.response = response
        self.ad = response.ad
    }

    public static func load(slotId: String, format: String? = nil) async throws -> RewardedAd {
        guard let pluga = AdPluga.maybeInstance else { throw AdPlugaError.notInitialized }
        guard let response = await pluga.serve(slotId: slotId, format: format) else {
            throw AdPlugaError.network(statusCode: -1, detail: "no fill")
        }
        switch response.ad.kind {
        case .image, .template, .video, .videoRewarded:
            return RewardedAd(slotId: slotId, response: response)
        default:
            throw AdPlugaError.unsupportedFormat(response.ad.kind.wire)
        }
    }

    @MainActor
    public func show(from presenter: UIViewController, onReward: @escaping RewardCallback, onDismiss: (() -> Void)? = nil) async {
        guard let pluga = AdPluga.maybeInstance else { return }
        let duration = Self.computeDurationSeconds(ad.durationMs)
        let rewardAmount = ad.rewardAmount ?? 1
        let rewardCurrency = ad.rewardCurrency
        let isVideo = ad.kind == .videoRewarded || ad.kind == .video
        let videoUrl: URL? = isVideo ? ad.assetUrl.flatMap { URL(string: $0) } : nil
        let image: UIImage?
        if !isVideo, let raw = ad.assetUrl, let url = URL(string: raw) {
            image = await Self.loadImage(url)
        } else {
            image = nil
        }
        if !isVideo && image == nil {
            onDismiss?()
            return
        }
        let controller = RewardedViewController(
            image: image,
            videoUrl: videoUrl,
            quartilePings: response.quartilePings,
            clickThroughUrl: response.clickUrl.flatMap { URL(string: $0) },
            durationSeconds: duration,
            skippableAfterMs: ad.skippableAfterMs ?? 0,
            onClick: { [weak self, weak pluga] in
                guard let self = self, let pluga = pluga else { return }
                pluga.fireClick(slotId: self.slotId, ad: self.ad, url: self.response.clickUrl, token: self.response.clickToken)
            },
            onReward: { onReward(rewardAmount, rewardCurrency) },
            onDismiss: { onDismiss?() }
        )
        controller.modalPresentationStyle = .fullScreen
        controller.onShow = { [weak self, weak pluga] in
            guard let self = self, let pluga = pluga, !self.impressionFired else { return }
            self.impressionFired = true
            pluga.fireImpression(slotId: self.slotId, ad: self.ad, url: self.response.impressionUrl, token: self.response.impressionToken)
            pluga.fireViewable(slotId: self.slotId, ad: self.ad, token: self.response.impressionToken)
        }
        presenter.present(controller, animated: true)
    }

    private static func computeDurationSeconds(_ ms: Int?) -> Int {
        let raw = ms ?? 5000
        let seconds = Int((Double(raw) / 1000.0).rounded(.up))
        return min(max(seconds, 1), 60)
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

final class RewardedViewController: UIViewController, AdPlugaVideoViewDelegate {
    private let image: UIImage?
    private let videoUrl: URL?
    private let quartilePings: [String: String]?
    private let clickThroughUrl: URL?
    private let durationSeconds: Int
    private let skippableAfterMs: Int
    private let onClick: () -> Void
    private let onReward: () -> Void
    private let onDismiss: () -> Void
    var onShow: (() -> Void)?

    private var remaining: Int
    private let countdownLabel = UILabel()
    private let closeBtn = UIButton(type: .system)
    private var timer: Timer?
    private var rewarded = false
    private var videoView: AdPlugaVideoView?

    private var isVideo: Bool { videoUrl != nil }

    init(
        image: UIImage?,
        videoUrl: URL?,
        quartilePings: [String: String]?,
        clickThroughUrl: URL?,
        durationSeconds: Int,
        skippableAfterMs: Int,
        onClick: @escaping () -> Void,
        onReward: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.image = image
        self.videoUrl = videoUrl
        self.quartilePings = quartilePings
        self.clickThroughUrl = clickThroughUrl
        self.durationSeconds = durationSeconds
        self.skippableAfterMs = skippableAfterMs
        self.remaining = durationSeconds
        self.onClick = onClick
        self.onReward = onReward
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
            video.openClickExternally = false
            view.addSubview(video)
            NSLayoutConstraint.activate([
                video.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                video.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                video.topAnchor.constraint(equalTo: view.topAnchor),
                video.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
            videoView = video
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
        }

        countdownLabel.text = String(remaining)
        countdownLabel.textColor = .white
        countdownLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        countdownLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(countdownLabel)
        NSLayoutConstraint.activate([
            countdownLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            countdownLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
        ])

        closeBtn.setTitle("\u{00D7}", for: .normal)
        closeBtn.setTitleColor(.white, for: .normal)
        closeBtn.titleLabel?.font = .systemFont(ofSize: 32, weight: .bold)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.isHidden = true
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
        if !isVideo {
            startStaticTimer()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timer?.invalidate()
        timer = nil
        videoView?.teardown()
    }

    private func startStaticTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.remaining -= 1
            if self.remaining <= 0 {
                self.countdownLabel.isHidden = true
                self.closeBtn.isHidden = false
                self.timer?.invalidate()
                self.timer = nil
                self.grantReward()
            } else {
                self.countdownLabel.text = String(self.remaining)
            }
        }
    }

    private func grantReward() {
        guard !rewarded else { return }
        rewarded = true
        onReward()
    }

    @objc private func handleTap() { onClick() }

    @objc private func handleClose() {
        dismiss(animated: true) { [weak self] in
            self?.onDismiss()
        }
    }

    func adPlugaVideoViewDidClick(_ view: AdPlugaVideoView) { onClick() }

    func adPlugaVideoView(_ view: AdPlugaVideoView, didUpdatePosition positionMs: Int, durationMs: Int) {
        guard durationMs > 0 else { return }
        let remainingMs = max(0, durationMs - positionMs)
        let secs = Int((Double(remainingMs) / 1000.0).rounded(.up))
        if countdownLabel.text != String(secs) {
            countdownLabel.text = String(secs)
        }
        if skippableAfterMs > 0 && positionMs >= skippableAfterMs {
            countdownLabel.isHidden = true
            closeBtn.isHidden = false
        }
    }

    func adPlugaVideoViewDidComplete(_ view: AdPlugaVideoView) {
        countdownLabel.isHidden = true
        closeBtn.isHidden = false
        grantReward()
    }
}
#endif
