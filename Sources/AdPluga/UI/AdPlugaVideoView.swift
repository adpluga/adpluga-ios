#if canImport(UIKit)
import AVFoundation
import UIKit

public protocol AdPlugaVideoViewDelegate: AnyObject {
    func adPlugaVideoViewDidClick(_ view: AdPlugaVideoView)
    func adPlugaVideoViewDidComplete(_ view: AdPlugaVideoView)
    func adPlugaVideoView(_ view: AdPlugaVideoView, didUpdatePosition positionMs: Int, durationMs: Int)
}

public extension AdPlugaVideoViewDelegate {
    func adPlugaVideoViewDidClick(_ view: AdPlugaVideoView) {}
    func adPlugaVideoViewDidComplete(_ view: AdPlugaVideoView) {}
    func adPlugaVideoView(_ view: AdPlugaVideoView, didUpdatePosition positionMs: Int, durationMs: Int) {}
}

public final class AdPlugaVideoView: UIView {
    public weak var delegate: AdPlugaVideoViewDelegate?
    public var clickThroughUrl: URL?
    public var openClickExternally: Bool = true

    private let playerLayer = AVPlayerLayer()
    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var completeObserver: NSObjectProtocol?
    private var quartileFirer: QuartileFirer?
    private var completed = false
    private var clickFired = false

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
        layer.addSublayer(playerLayer)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
        isUserInteractionEnabled = true
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }

    public func load(videoUrl: URL?, quartilePings: [String: String]? = nil) {
        teardown()
        guard let url = videoUrl, Self.isAllowedScheme(url) else { return }
        quartileFirer = QuartileFirer(pings: quartilePings)
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .pause
        self.player = player
        playerLayer.player = player
        addPeriodicObserver(player: player)
        addCompleteObserver(item: item)
        player.play()
    }

    private func addPeriodicObserver(player: AVPlayer) {
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            guard let self = self, let currentItem = player.currentItem else { return }
            let duration = currentItem.duration
            let durationSeconds: Double = duration.isNumeric ? CMTimeGetSeconds(duration) : 0
            let positionSeconds = CMTimeGetSeconds(time)
            guard durationSeconds > 0, positionSeconds.isFinite else { return }
            let posMs = Int(positionSeconds * 1000)
            let durMs = Int(durationSeconds * 1000)
            self.quartileFirer?.update(positionMs: posMs, durationMs: durMs)
            self.delegate?.adPlugaVideoView(self, didUpdatePosition: posMs, durationMs: durMs)
        }
    }

    private func addCompleteObserver(item: AVPlayerItem) {
        completeObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, !self.completed else { return }
            self.completed = true
            let duration = item.duration
            if duration.isNumeric {
                let durMs = Int(CMTimeGetSeconds(duration) * 1000)
                self.quartileFirer?.update(positionMs: durMs, durationMs: durMs)
            }
            self.delegate?.adPlugaVideoViewDidComplete(self)
        }
    }

    @objc private func handleTap() {
        guard !clickFired else { return }
        clickFired = true
        delegate?.adPlugaVideoViewDidClick(self)
        guard openClickExternally, let url = clickThroughUrl, Self.isAllowedScheme(url) else {
            return
        }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    public override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil {
            teardown()
        }
    }

    public func teardown() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        if let obs = completeObserver {
            NotificationCenter.default.removeObserver(obs)
            completeObserver = nil
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        playerLayer.player = nil
        player = nil
        quartileFirer = nil
        completed = false
        clickFired = false
    }

    deinit {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
        }
        if let obs = completeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    static func isAllowedScheme(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
#endif
