import Foundation

/// Label VoiceOver announces in place of the creative. An ad is never
/// decorative — it carries meaning and opens a destination — so an unlabelled
/// image leaves the tap target with no name at all (WCAG 2.2 SC 1.1.1 and
/// SC 2.4.4, both level A). Falls back to the title, then to a neutral word,
/// which is still a name.
func adLabel(_ ad: Ad) -> String {
    if let alt = ad.altText, !alt.trimmingCharacters(in: .whitespaces).isEmpty {
        return alt
    }
    if let title = ad.nativeAssets?["title"], !title.trimmingCharacters(in: .whitespaces).isEmpty {
        return title
    }
    return "Anuncio"
}

/// Slides share the ad's destination, so a card with no copy of its own
/// inherits the ad's label rather than going unnamed.
func slideLabel(_ ad: Ad, _ slide: Slide) -> String {
    if let title = slide.title, !title.trimmingCharacters(in: .whitespaces).isEmpty {
        return title
    }
    return adLabel(ad)
}
