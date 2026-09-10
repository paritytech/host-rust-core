import Foundation
import ExtrinsicService
import SubstrateSdk
import Operation_iOS
import Keystore_iOS
import KeyDerivation
import Individuality

protocol CandidateOriginFactoryProtocol: ExtrinsicOriginFactoryProtocol {
    func createAsParticipantAsReferred(
        for wallet: WalletManaging,
        chain: ChainProtocol
    ) throws -> ExtrinsicOriginDefining

    func createAsParticipantAsInvited(
        for wallet: WalletManaging,
        chain: ChainProtocol
    ) throws -> ExtrinsicOriginDefining

    func createGameAsInvited(
        for wallet: WalletManaging,
        chain: ChainProtocol,
        inviter: AccountId,
        ticket: AccountId,
        signature: MultiSignature
    ) throws -> ExtrinsicOriginDefining

    func createSignedScoreAsParticipant(
        for wallet: WalletManaging,
        chain: ChainProtocol
    ) throws -> ExtrinsicOriginDefining
}

extension CandidateOriginFactoryProtocol {
    func createPersonRegistrationDefinition(
        for candidateType: PersonRegistration.CandidateType,
        wallet: WalletManaging,
        chain: ChainProtocol
    ) throws -> ExtrinsicOriginDefining {
        switch candidateType {
        case let .proofOfInk(proofOfInkType):
            try createPersonRegistrationDefinition(
                for: proofOfInkType,
                wallet: wallet,
                chain: chain
            )
        case .game:
            try createSignedScoreAsParticipant(for: wallet, chain: chain)
        }
    }

    private func createPersonRegistrationDefinition(
        for candidateType: PersonRegistration.ProofOfInkCandidateType,
        wallet: WalletManaging,
        chain: ChainProtocol
    ) throws -> ExtrinsicOriginDefining {
        switch candidateType {
        case .referred:
            try createAsParticipantAsReferred(for: wallet, chain: chain)
        case .deposit:
            try createSignedOrigin(for: wallet, chain: chain)
        case .invited:
            try createAsParticipantAsInvited(for: wallet, chain: chain)
        }
    }
}

final class CandidateOriginFactory: ExtrinsicOriginFactory {}

extension CandidateOriginFactory: CandidateOriginFactoryProtocol {
    func createAsParticipantAsReferred(
        for wallet: WalletManaging,
        chain: ChainProtocol
    ) throws -> ExtrinsicOriginDefining {
        let accountOrigin = try createAccountOrigin(for: wallet, chain: chain)
        let referredOrigin = AsParticipantOriginDefinition(mode: .asReferred)
        let signedOrigin = try createSigningByAccountOrigin(for: wallet, chain: chain)
        let restrictionOrigin = RestrictsOriginDefinition(enabled: true)

        return ExtrinsicCompoundOrigin(children: [accountOrigin, restrictionOrigin, referredOrigin, signedOrigin])
    }

    func createAsParticipantAsInvited(
        for wallet: WalletManaging,
        chain: ChainProtocol
    ) throws -> ExtrinsicOriginDefining {
        let accountOrigin = try createAccountOrigin(for: wallet, chain: chain)
        let referredOrigin = AsParticipantOriginDefinition(mode: .asInvited)
        let signedOrigin = try createSigningByAccountOrigin(for: wallet, chain: chain)
        let restrictionOrigin = RestrictsOriginDefinition(enabled: true)

        return ExtrinsicCompoundOrigin(children: [accountOrigin, restrictionOrigin, referredOrigin, signedOrigin])
    }

    func createGameAsInvited(
        for wallet: WalletManaging,
        chain: ChainProtocol,
        inviter: AccountId,
        ticket: AccountId,
        signature: MultiSignature
    ) throws -> ExtrinsicOriginDefining {
        let accountOrigin = try createAccountOrigin(for: wallet, chain: chain)

        let signedOrigin = try createSigningByAccountOrigin(for: wallet, chain: chain)

        let restrictionOrigin = RestrictsOriginDefinition(enabled: false)

        let gameAsInvited = AsGameInvitedOriginDefinition(
            inviter: inviter,
            ticket: ticket,
            signature: signature
        )

        return ExtrinsicCompoundOrigin(children: [
            accountOrigin,
            restrictionOrigin,
            gameAsInvited,
            signedOrigin
        ])
    }

    func createSignedScoreAsParticipant(
        for wallet: WalletManaging,
        chain: ChainProtocol
    ) throws -> ExtrinsicOriginDefining {
        let accountOrigin = try createAccountOrigin(for: wallet, chain: chain)
        let signedOrigin = try createSigningByAccountOrigin(for: wallet, chain: chain)
        let restrictionOrigin = RestrictsOriginDefinition(enabled: true)
        let scoreAsParticipant = ScoreAsParticipantOriginDefinition()

        return ExtrinsicCompoundOrigin(children: [
            accountOrigin,
            restrictionOrigin,
            scoreAsParticipant,
            signedOrigin
        ])
    }
}
