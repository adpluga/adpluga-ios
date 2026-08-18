# Changelog

All notable changes to the AdPluga iOS SDK are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.4.1] — 2026-08

### Fixed
- Aligned the serve response contract to the current backend: the SDK now
  reads `type`, `track_token` and a top-level `source`, plus flat native
  fields (`title`, `body`, `cta_text`, `sponsored_by`, `icon_url`,
  `main_image_url`). It previously decoded a stale shape
  (`kind`/`impression_token`/`native_assets`) and failed to parse live
  serve responses.

## [0.4.0] — 2026-07

### Fixed
- QuartileFirer now resolves relative ping URLs against the SDK endpoint
  using `URL(string:relativeTo:)`, fixing quartile tracking when the
  backend returns relative paths.
- VideoAdView passes `pluga.endpoint` to QuartileFirer initializer.

## [0.3.0] — 2026-07

### Added
- IAB viewability dispatch: `AdPluga.fireViewable(slotId:ad:token:)` posts
  `/v1/track/viewable` from the same viewability callback that already
  recorded the impression on `AdPlugaView`, `NativeAd`, `InterstitialAd`
  and `RewardedAd`.

## [0.2.0] — 2025-11

### Added
- HTML5 / WebView ad format via `WKWebView`.
- Video and rewarded video via `AVPlayer` + `AVPlayerLayer`
  with VAST-style quartile beacons.
- `QuartileFirer` helper (fire-and-forget beacons at 0/25/50/75/100%).

### Changed
- Rewarded countdown is now driven by `AVPlayer.addPeriodicTimeObserver`
  instead of a static timer.

## [0.1.0] — 2025-10

### Added
- Initial public release: banner, native, and interstitial formats.
- `AdBannerView` `UIView` subclass and `AdPlugaDelegate` protocol.
- `CADisplayLink`-based viewability tracker and consent adapter.
