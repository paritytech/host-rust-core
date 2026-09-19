import Foundation
import Keystore_iOS

/// Internal, not private, so a test can pin the getter against it: the test target carries no
/// `-DFEATURE_*` flags and would otherwise read the opposite arm from the module it tests.
#if FEATURE_DIMS
    let defaultHostPlacementEnabled = false
#else
    let defaultHostPlacementEnabled = true
#endif

extension SettingsManagerProtocol {
    /// Whether the host puts its designated products in chat itself.
    ///
    /// Off by default on a `FEATURE_DIMS` build, which already shows the same game through the
    /// native DIM2 extension under a chat identity of its own, and nothing dedupes the pair.
    /// A stored choice wins either way; Release has no debug screen, so there the placement stands.
    /// The default cannot live in `value(for:)` — that helper is shared by every boolean setting.
    var isHostPlacementEnabled: Bool {
        bool(for: SettingsKey.hostPlacementEnabled.rawValue) ?? defaultHostPlacementEnabled
    }
}
