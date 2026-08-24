#if canImport(UIKit)
import UIKit

// Non-interactive "TEST" marker drawn over sandbox creatives served by a
// pk_test_ key, mirroring the web SDK badge (orange, top-left, high z-order).
enum TestBadge {
    private static let background = UIColor(red: 180.0 / 255.0, green: 83.0 / 255.0, blue: 9.0 / 255.0, alpha: 1.0)

    @MainActor
    @discardableResult
    static func attach(to container: UIView) -> UIView {
        let badge = TestBadgeLabel()
        badge.text = "TEST"
        badge.textColor = .white
        badge.font = .systemFont(ofSize: 10, weight: .bold)
        badge.backgroundColor = background
        badge.layer.cornerRadius = 4
        badge.layer.masksToBounds = true
        badge.isUserInteractionEnabled = false
        badge.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(badge)
        container.bringSubviewToFront(badge)
        let guide = container.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            badge.topAnchor.constraint(equalTo: guide.topAnchor, constant: 4),
            badge.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 4),
        ])
        return badge
    }
}

final class TestBadgeLabel: UILabel {
    private let insets = UIEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let base = super.intrinsicContentSize
        return CGSize(width: base.width + insets.left + insets.right, height: base.height + insets.top + insets.bottom)
    }
}
#endif
