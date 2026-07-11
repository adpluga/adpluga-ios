#if canImport(UIKit)
import UIKit
import WebKit

public protocol AdPlugaHtmlViewDelegate: AnyObject {
    func adPlugaHtmlViewDidClick(_ view: AdPlugaHtmlView)
}

public final class AdPlugaHtmlView: UIView {
    public weak var delegate: AdPlugaHtmlViewDelegate?

    private let webView: WKWebView
    private let navigationHandler = _NavigationHandler()

    public override init(frame: CGRect) {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.dataDetectorTypes = []
        config.suppressesIncrementalRendering = false
        let prefs = WKPreferences()
        prefs.javaScriptCanOpenWindowsAutomatically = false
        config.preferences = prefs
        if #available(iOS 14.0, *) {
            let pagePrefs = WKWebpagePreferences()
            pagePrefs.allowsContentJavaScript = true
            config.defaultWebpagePreferences = pagePrefs
        }
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init(frame: frame)
        setup()
    }

    public required init?(coder: NSCoder) {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.dataDetectorTypes = []
        let prefs = WKPreferences()
        prefs.javaScriptCanOpenWindowsAutomatically = false
        config.preferences = prefs
        if #available(iOS 14.0, *) {
            let pagePrefs = WKWebpagePreferences()
            pagePrefs.allowsContentJavaScript = true
            config.defaultWebpagePreferences = pagePrefs
        }
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.allowsBackForwardNavigationGestures = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        navigationHandler.onClick = { [weak self] in
            guard let self = self else { return }
            self.delegate?.adPlugaHtmlViewDidClick(self)
        }
        webView.navigationDelegate = navigationHandler
    }

    public func load(html: String?, assetUrl: URL? = nil, baseURL: URL? = nil) {
        navigationHandler.initialLoaded = false
        if let html = html, !html.isEmpty {
            webView.loadHTMLString(html, baseURL: baseURL)
        } else if let url = assetUrl, Self.isAllowedScheme(url) {
            webView.load(URLRequest(url: url))
        }
    }

    public func stop() {
        webView.stopLoading()
        webView.navigationDelegate = nil
    }

    static func isAllowedScheme(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

final class _NavigationHandler: NSObject, WKNavigationDelegate {
    var initialLoaded = false
    var onClick: (() -> Void)?

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if !initialLoaded {
            initialLoaded = true
            decisionHandler(.allow)
            return
        }
        guard let url = navigationAction.request.url, AdPlugaHtmlView.isAllowedScheme(url) else {
            decisionHandler(.cancel)
            return
        }
        onClick?()
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        decisionHandler(.cancel)
    }
}
#endif
