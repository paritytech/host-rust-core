import Foundation
import KeyDerivation
import NovaCrypto
import SubstrateSdk
import Testing

@testable import polkadot_app

@Suite("AirdropVrfTranscript Tests")
struct AirdropVrfTranscriptTests {
    let wallet = SsoTestData.makeWallet(derivationPath: "//airdrop-transcript-tests")

    // The airdrop transcript is chain-consensus-critical: a byte slip here verifies
    // locally but silently breaks on-chain lottery tickets.
    @Test("Recipe matches the pre-refactor hardcoded construction")
    func recipeMatchesLegacyConstruction() throws {
        let eventId = try Data.randomOrError(of: 32)
        let publicKey = try wallet.getRawPublicKey()

        // Recipe bytes pinned against AirdropVrfSigner as of its deletion.
        let expectedLabel = Data("pop:airdrop".utf8)
        #expect(AirdropVrfTranscript.label == expectedLabel)

        let items = AirdropVrfTranscript.items(eventId: eventId, publicKey: publicKey)
        #expect(items.count == 2)
        #expect(items[0] == VrfTranscriptItem(label: Data("domain".utf8), value: expectedLabel + eventId))
        #expect(items[1] == VrfTranscriptItem(label: Data("signer".utf8), value: publicKey))

        // The generic signer replays the recipe identically to the legacy direct call.
        let refactored = try Sr25519VrfSigner.sign(
            wallet: wallet,
            transcriptLabel: AirdropVrfTranscript.label,
            items: items
        )

        let snKeypair = try SNKeypair(
            privateKey: SNPrivateKey(rawData: wallet.fetchRawSecretKey()),
            publicKey: SNPublicKey(rawData: publicKey)
        )
        let legacyFields = [
            SNVrfField(key: Data("domain".utf8), value: expectedLabel + eventId),
            SNVrfField(key: Data("signer".utf8), value: publicKey)
        ]
        let legacy = try SNVrfSigner(keypair: snKeypair).sign(
            withLabel: expectedLabel,
            fields: legacyFields
        )

        #expect(refactored.preOutput == legacy.preOutput)
    }
}
