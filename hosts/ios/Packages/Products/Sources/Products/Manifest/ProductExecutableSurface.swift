import Foundation

/// Which of a product's executables a screen serves.
///
/// The origin is the product's base domain either way, so permission grants and
/// web storage stay keyed to the product rather than to the surface.
public enum ProductExecutableSurface: Sendable {
    case app
    /// A Pocket card opened from the collection. The protocol names the widget
    /// as what an expanded card runs.
    case widget
}
