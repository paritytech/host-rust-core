import Foundation

struct IssueInvitationResponse: Decodable {
    /// The SS58 address of the inviter.
    var inviter: String
    /// SS58 address of the claimant (owner)
    var claimedBy: String
    /// Public key of the claimed ticket
    var publicKey: String
    /// Hex-encoded signature by the ticket key over the claimant's AccountId bytes.
    var signature: String
}
