# Changelog

All notable changes to the AdPluga iOS SDK are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.5.0] — 2026-09

### Added
- Slot rotation: `AdPlugaView` now re-serves on the cadence the publisher
  configures for the slot (`refresh_after_seconds` on the serve response), so a
  long-lived screen no longer shows a single frozen creative.
- Rotation is gated so it cannot waste the publisher's budget or produce
  non-viewable impressions: it only fires while the view meets the IAB pixel
  threshold (`ViewabilityTracker.isVisible`) and the app is in the foreground,
  is floored at 30s (`Constants.minRefreshSeconds`), and the timer is
  invalidated on background, on reload and on deinit.
- Each rotation sends its index (`rq`) so refreshed impressions stay segregable
  from the initial render, as the MRC guidelines require.

## [0.4.2] — 2026-08

### Added
- Test-mode badge: creatives served by a `pk_test_` key now carry the
  authoritative `test` flag on the serve response (`Ad.isTest`), and every
  render surface (`AdPlugaView`, native, interstitial and rewarded) draws a
  small non-interactive orange "TEST" marker so sandbox ads are visually
  distinguishable from live ones.

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
