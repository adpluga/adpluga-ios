# AdPluga iOS SDK

Native iOS SDK for ad serving with pluggable server-side mediation.
Talks to the AdPluga edge (`/v1/serve` + `/v1/track`) and renders banner,
native, interstitial, rewarded, HTML5, and video formats.

- **Distribution**: Swift Package Manager (primary) · CocoaPods (planned)
- **iOS**: 14.0+ · **Swift**: 5.9+
- **Zero external dependencies** (Foundation, UIKit, CryptoKit only)
- **License**: Proprietary — see [LICENSE](./LICENSE)

## Why AdPluga

- **100,000 ad decisions free every month.** No card, no expiry.
- **No traffic minimum.** When there is no demand, a house ad fills the slot so it never renders empty.
- **Test mode first.** A `pk_test_` key serves ads with no billing and no quota use; switch to `pk_live_` when you are ready.
- **One integration, every demand source.** Direct deals, network demand and mediation behind the same slot.

Create a free account at <https://adpluga.com/en/> and get your keys in the dashboard.

## Install (Swift Package Manager)

Xcode → File → Add Packages… → enter:

```
https://github.com/adpluga/adpluga-ios.git
```

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/adpluga/adpluga-ios.git", from: "0.7.3"),
]
```

## Quick start

```swift
import AdPluga

// AppDelegate: initialize throws on a malformed key.
try AdPluga.initialize(publisherKey: "pk_test_...")

// A view controller
let banner = AdPlugaView(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
banner.delegate = self
view.addSubview(banner)
banner.load(slotId: "your-slot-id")
```

`AdPlugaView` is a `UIView`; in SwiftUI, wrap it in a `UIViewRepresentable`. iOS 14+.

Integration guides and API reference: <https://adpluga.com/en/devs/sdks/> · quick start in two minutes: <https://adpluga.com/en/devs/quickstart/>.

## Support

- Issues and questions: <https://github.com/adpluga/adpluga-ios/issues>
- Security disclosures: <security@adpluga.com>

This repository is a read-only mirror of the internal monorepo. Pull requests
are accepted for discussion but changes are integrated upstream.
