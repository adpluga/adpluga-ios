# AdPluga iOS SDK

Native iOS SDK for ad serving with pluggable server-side mediation.
Talks to the AdPluga edge (`/v1/serve` + `/v1/track`) and renders banner,
native, interstitial, rewarded, HTML5, and video formats.

- **Distribution**: Swift Package Manager (primary) · CocoaPods (planned)
- **iOS**: 14.0+ · **Swift**: 5.9+
- **Zero external dependencies** (Foundation, UIKit, CryptoKit only)
- **License**: Proprietary — see [LICENSE](./LICENSE)

## Install (Swift Package Manager)

Xcode → File → Add Packages… → enter:

```
https://github.com/adpluga/adpluga-ios.git
```

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/adpluga/adpluga-ios.git", from: "0.2.0"),
]
```

## Quick start

```swift
import AdPluga

// AppDelegate.swift
AdPluga.initialize(publisherKey: "pk_live_...")

// UIView
let bannerView = AdBannerView(slotId: "slot_home", format: "banner_320x100")
bannerView.delegate = self
bannerView.load()

// SwiftUI
struct HomeAd: View {
    var body: some View {
        AdPlugaBannerView(slotId: "slot_home", format: "banner_320x100")
    }
}
```

Full API reference and integration guides: <https://app.adpluga.com/docs/sdk/ios>.

## Support

- Issues and questions: <https://github.com/adpluga/adpluga-ios/issues>
- Security disclosures: <security@adpluga.com>

This repository is a read-only mirror of the internal monorepo. Pull requests
are accepted for discussion but changes are integrated upstream.
