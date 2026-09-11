import Foundation
import SubstrateSdk
import KeyDerivation
import Individuality

enum AirdropProofFactoryError: Error {
    case missingRingRevision
}

protocol AirdropProofFactoryProtocol {
    /// Forms the airdrop VRF proof for a player signing up, choosing the variant the runtime expects:
    /// - not recognized → sr25519 **Account** proof;
    /// - recognized + member key included in the people ring → bandersnatch **Alias** proof;
    /// - recognized but not yet included → `nil` (no proof can be formed; sign-up proceeds without airdrop).
    func makeProof(
        gameIndex: GamePallet.GameIndex,
        player: GamePallet.AccountOrPerson
    ) async throws -> GamePallet.AirdropVrfs?
}

final class AirdropProofFactory {
    private let candidateWallet: WalletManaging
    private let personVrfManager: BandersnatchKeyManaging
    private let proofParamsFetcher: MembershipProofParamsFetching
    private let memberService: GameMemberServicing
    private let membershipStatusChecker: MembershipStatusChecking
    private let collectionId: MembersPallet.CollectionIdentifier

    init(
        candidateWallet: WalletManaging,
        personVrfManager: BandersnatchKeyManaging,
        proofParamsFetcher: MembershipProofParamsFetching,
        memberService: GameMemberServicing,
        membershipStatusChecker: MembershipStatusChecking,
        collectionId: MembersPallet.CollectionIdentifier = PeoplePallet.membersIdentifier
    ) {
        self.candidateWallet = candidateWallet
        self.personVrfManager = personVrfManager
        self.proofParamsFetcher = proofParamsFetcher
        self.memberService = memberService
        self.membershipStatusChecker = membershipStatusChecker
        self.collectionId = collectionId
    }
}

extension AirdropProofFactory: AirdropProofFactoryProtocol {
    func makeProof(
        gameIndex: GamePallet.GameIndex,
        player: GamePallet.AccountOrPerson
    ) async throws -> GamePallet.AirdropVrfs? {
        let memberInfo = try await memberService.fetchMemberInfo(player: player, blockHash: nil)
        let isRecognized = memberInfo?.isRecognized ?? false

        Logger.shared.debug(
            "[GameDebug] airdropProof.make: gameIndex=\(gameIndex) recognized=\(isRecognized) "
                + "player=\(player.rawTypeValue)"
        )

        guard isRecognized else {
            return try makeAccountProof(gameIndex: gameIndex)
        }

        let memberKey = try personVrfManager.getMemberKey()
        let ringIndexByKey = try await membershipStatusChecker.checkStatuses(
            of: [MembershipStatusInput(memberKey: memberKey, collection: collectionId)],
            blockHash: nil
        )

        guard let ringIndex = ringIndexByKey[memberKey] else {
            Logger.shared.debug(
                "[GameDebug] airdropProof.make: recognized but member key not in ring -> no airdrop proof"
            )
            return nil
        }

        return try await makeAliasProof(gameIndex: gameIndex, player: player, ringIndex: ringIndex)
    }
}

private extension AirdropProofFactory {
    func makeAccountProof(gameIndex: GamePallet.GameIndex) throws -> GamePallet.AirdropVrfs {
        let eventId = NewAirdropPallet.gameEventId(forGameIndex: gameIndex, airdropIndex: 0)

        Logger.shared.debug(
            "[GameDebug] airdropProof.account: gameIndex=\(gameIndex) "
                + "eventId=\(eventId.toHex())"
        )

        let signature = try Sr25519VrfSigner.sign(
            wallet: candidateWallet,
            transcriptLabel: AirdropVrfTranscript.label,
            items: AirdropVrfTranscript.items(
                eventId: eventId,
                publicKey: candidateWallet.getRawPublicKey()
            )
        )

        Logger.shared.debug(
            "[GameDebug] airdropProof.account: SIGNED variant=Account "
                + "preOutput=\(signature.preOutput.toHex()) proofLen=\(signature.proof.count) "
                + "proofPrefix=\(signature.proof.prefix(8).toHex())"
        )

        return .account([Sr25519VrfSignature(preOutput: signature.preOutput, proof: signature.proof)])
    }

    func makeAliasProof(
        gameIndex: GamePallet.GameIndex,
        player: GamePallet.AccountOrPerson,
        ringIndex: MembersPallet.RingIndex
    ) async throws -> GamePallet.AirdropVrfs {
        let context = try NewAirdropPallet.airdropContext(forGameIndex: gameIndex, airdropIndex: 0)
        let message = NewAirdropPallet.RegistrationEntry.proofMessage(for: player)

        Logger.shared.debug(
            "[GameDebug] airdropProof.alias: gameIndex=\(gameIndex) ringIndex=\(ringIndex) "
                + "message=\(message.toHex(includePrefix: true)) context=\(context.toHex(includePrefix: true))"
        )

        let proofParams = try await proofParamsFetcher.fetchOrError(
            for: ringIndex,
            collectionId: collectionId,
            blockHash: nil
        )

        guard let ringRevision = try await proofParamsFetcher.fetchCurrentRevision(
            for: ringIndex,
            collectionId: collectionId,
            blockHash: nil
        ) else {
            throw AirdropProofFactoryError.missingRingRevision
        }

        let ownKey = try personVrfManager.getMemberKey()
        let ownKeyIndex = proofParams.ringMembers.firstIndex(of: ownKey)
        let membersFingerprint = try proofParams.ringMembers
            .reduce(into: Data()) { $0.append($1) }
            .blake2b32()

        Logger.shared.debug(
            "[GameDebug] airdropProof.alias: fetched ringMembers=\(proofParams.ringMembers.count) "
                + "domainSize=\(String(describing: proofParams.ringSize)) "
                + "ownKey=\(ownKey.toHex(includePrefix: true)) ownKeyInRing=\(ownKeyIndex != nil) "
                + "ownKeyIndex=\(ownKeyIndex.map(String.init) ?? "absent") "
                + "membersBlake2=\(membersFingerprint.toHex(includePrefix: true)) usedRevision=\(ringRevision)"
        )

        let proof = try personVrfManager.createProof(
            message,
            members: proofParams.ringMembers,
            context: context,
            domainSize: proofParams.ringSize
        )

        Logger.shared.debug(
            "[GameDebug] airdropProof.alias: PROOF variant=Alias proofLen=\(proof.count) "
                + "(expected 785) ringIndex=\(ringIndex) revision=\(ringRevision)"
        )

        return .alias(
            .init(
                proofs: [proof],
                ringIndex: ringIndex,
                revision: ringRevision
            )
        )
    }
}
