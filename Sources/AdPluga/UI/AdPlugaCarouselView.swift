#if canImport(UIKit)
import UIKit

/// Renders a carousel deck as a paged `UIScrollView`, so it inherits UIKit's
/// own deceleration and paging instead of reimplementing them.
///
/// The deck is one advertiser and one auction: every card reports the same tap
/// through `onClick` and the view never requests another creative. `onSwipe`
/// fires when the settled card changes so the host can hold off a scheduled
/// rotation rather than replacing the deck mid-read.
final class AdPlugaCarouselView: UIView, UIScrollViewDelegate {
    var onClick: (() -> Void)?
    var onSwipe: (() -> Void)?

    private let scrollView: UIScrollView = {
        let view = UIScrollView()
        view.isPagingEnabled = true
        view.showsHorizontalScrollIndicator = false
        view.showsVerticalScrollIndicator = false
        view.bounces = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let pageControl: UIPageControl = {
        let control = UIPageControl()
        control.isUserInteractionEnabled = false
        control.hidesForSinglePage = true
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    private var cards: [UIView] = []
    private var page = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupSubviews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupSubviews()
    }

    private func setupSubviews() {
        backgroundColor = .clear
        scrollView.delegate = self
        addSubview(scrollView)
        addSubview(pageControl)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            pageControl.centerXAnchor.constraint(equalTo: centerXAnchor),
            pageControl.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        scrollView.addGestureRecognizer(tap)
    }

    /// Mounts one card per slide. `images` is index-aligned with `slides`; a
    /// slide whose creative failed to load keeps its place with an empty card
    /// so the deck order the advertiser arranged is never silently reshuffled.
    func bind(slides: [Slide], images: [UIImage?], fallbackLabel: String = "Anuncio") {
        for card in cards { card.removeFromSuperview() }
        cards = []
        page = 0
        pageControl.numberOfPages = slides.count
        pageControl.currentPage = 0

        var previous: UIView?
        for (i, slide) in slides.enumerated() {
            let card = makeCard(
                slide: slide,
                image: images.indices.contains(i) ? images[i] : nil,
                label: slide.title?.isEmpty == false ? slide.title! : fallbackLabel
            )
            scrollView.addSubview(card)
            NSLayoutConstraint.activate([
                card.topAnchor.constraint(equalTo: scrollView.topAnchor),
                card.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
                card.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
                card.leadingAnchor.constraint(
                    equalTo: previous?.trailingAnchor ?? scrollView.leadingAnchor
                ),
            ])
            cards.append(card)
            previous = card
        }
        if let last = previous {
            last.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor).isActive = true
        }
        setNeedsLayout()
    }

    func teardown() {
        for card in cards { card.removeFromSuperview() }
        cards = []
        onClick = nil
        onSwipe = nil
    }

    @objc private func handleTap() {
        onClick?()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        settle(scrollView)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { settle(scrollView) }
    }

    private func settle(_ scrollView: UIScrollView) {
        let width = scrollView.bounds.width
        guard width > 0 else { return }
        let current = Int((scrollView.contentOffset.x / width).rounded())
        guard current != page else { return }
        page = current
        pageControl.currentPage = current
        onSwipe?()
    }

    private func makeCard(slide: Slide, image: UIImage?, label: String) -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.clipsToBounds = true

        let imageView = UIImageView(image: image)
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = label
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: card.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])

        if let caption = makeCaption(slide: slide) {
            card.addSubview(caption)
            NSLayoutConstraint.activate([
                caption.leadingAnchor.constraint(equalTo: card.leadingAnchor),
                caption.trailingAnchor.constraint(equalTo: card.trailingAnchor),
                caption.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            ])
        }
        return card
    }

    private func makeCaption(slide: Slide) -> UIView? {
        let title = slide.title.flatMap { $0.isEmpty ? nil : $0 }
        let body = slide.body.flatMap { $0.isEmpty ? nil : $0 }
        let cta = slide.ctaText.flatMap { $0.isEmpty ? nil : $0 }
        if title == nil, body == nil, cta == nil { return nil }

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 6, left: 8, bottom: 18, right: 8)
        stack.backgroundColor = UIColor(white: 0.07, alpha: 0.82)
        stack.translatesAutoresizingMaskIntoConstraints = false

        if let title {
            stack.addArrangedSubview(makeLabel(title, size: 12, weight: .semibold, lines: 1))
        }
        if let body {
            stack.addArrangedSubview(makeLabel(body, size: 11, weight: .regular, lines: 2))
        }
        if let cta {
            let badge = makeLabel(cta, size: 10, weight: .semibold, lines: 1)
            badge.textColor = UIColor(white: 0.07, alpha: 1)
            badge.backgroundColor = .white
            badge.layer.cornerRadius = 3
            badge.clipsToBounds = true
            badge.textAlignment = .center
            stack.addArrangedSubview(badge)
            badge.heightAnchor.constraint(equalToConstant: 16).isActive = true
        }
        return stack
    }

    private func makeLabel(
        _ text: String,
        size: CGFloat,
        weight: UIFont.Weight,
        lines: Int
    ) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = .white
        label.numberOfLines = lines
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
}
#endif
