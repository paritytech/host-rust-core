import Foundation
import SubstrateSdk

/// The SDK leaves the format without `Hashable`; callers that cache per format need it as a key.
/// Remove once substrate-sdk-ios declares the conformance itself.
extension Extrinsic.Version: @retroactive Hashable {
    public static func == (lhs: Extrinsic.Version, rhs: Extrinsic.Version) -> Bool {
        switch (lhs, rhs) {
        case (.V4, .V4):
            true
        case let (.V5(lhsExtensionVersion), .V5(rhsExtensionVersion)):
            lhsExtensionVersion == rhsExtensionVersion
        case (.V4, .V5),
             (.V5, .V4):
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .V4:
            hasher.combine(4 as UInt8)
        case let .V5(extensionVersion):
            hasher.combine(5 as UInt8)
            hasher.combine(extensionVersion)
        }
    }
}
