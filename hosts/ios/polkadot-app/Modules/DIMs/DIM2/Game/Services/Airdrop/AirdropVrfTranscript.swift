import Foundation
import KeyDerivation

/// The merlin transcript recipe the People Chain airdrop signs, mirroring the runtime's
/// `indiv_pallet_airdrop::vrf::transcript_for_event`: root label `"pop:airdrop"`, then
/// `domain = label ++ eventId` and `signer = sr25519 public key`. A byte-order or ordering
/// slip here verifies fine locally but fails on-chain — pinned by `Sr25519VrfSignerTests`.
enum AirdropVrfTranscript {
    static let label = Data("pop:airdrop".utf8)

    static func items(eventId: Data, publicKey: Data) -> [VrfTranscriptItem] {
        [
            VrfTranscriptItem(label: Data("domain".utf8), value: label + eventId),
            VrfTranscriptItem(label: Data("signer".utf8), value: publicKey)
        ]
    }
}
