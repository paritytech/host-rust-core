import Foundation
import Keystore_iOS

extension SettingsManagerProtocol {
    /// Whether the host puts its designated products in chat itself.
    ///
    /// Off on `FEATURE_DIMS` builds: the native `WeeklyGame` extension is the same game as the
    /// host-placed `dim2.<tld>` product under a chat identity of its own, and nothing dedupes the
    /// pair. A stored choice wins either way. The default cannot live in `value(for:)` — that
    /// helper is shared by every boolean setting.
    var isHostPlacementEnabled: Bool {
        #if FEATURE_DIMS
            bool(for: SettingsKey.hostPlacementEnabled.rawValue) ?? false
        #else
            bool(for: SettingsKey.hostPlacementEnabled.rawValue) ?? true
        #endif
    }
}
