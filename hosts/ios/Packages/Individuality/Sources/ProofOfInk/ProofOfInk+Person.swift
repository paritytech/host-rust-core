import Foundation
import SubstrateSdk

public extension ProofOfInkPallet {
    struct Person: Decodable, Hashable {
        public let design: InkSpec?
        public let activeReferrals: [BytesCodable]
        @StringCodable public var badReferrals: UInt32
        @StringCodable public var successfulReferrals: UInt32
        @StringCodable public var referrals: UInt32
        @StringCodable public var derivatives: UInt32
        @StringCodable public var pendingReferralRewards: UInt32
        public let banned: Bool
    }
}
