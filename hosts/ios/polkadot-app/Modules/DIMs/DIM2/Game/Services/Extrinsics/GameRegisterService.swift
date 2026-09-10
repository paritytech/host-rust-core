import Foundation
import Operation_iOS
import Keystore_iOS
import SubstrateSdk
import ExtrinsicService
import KeyDerivation
import Individuality
import ChainRegistry

protocol GameRegisterServicing {
    func registerForGame(
        with mode: GameRegisterMode,
        airdrop: GamePallet.AirdropVrfs?
    ) -> CompoundOperationWrapper<ExtrinsicMonitorSubmission>

    func registerForGame(
        with invitation: Invitation,
        airdrop: GamePallet.AirdropVrfs?
    ) -> CompoundOperationWrapper<ExtrinsicMonitorSubmission>
}

enum GameRegisterMode {
    /// deposit is required
    case player(isCredible: Bool)
    /// player is person
    case scoreAlias(Data)
}

final class GameRegisterService {
    private let chain: ChainModel
    private let candidateWallet: WalletManaging
    private let scoreWallet: WalletManaging
    private let extrinsicSubmitMonitor: ExtrinsicSubmitMonitorFactoryProtocol
    private let encryptionIdentifier: Chat.OnChainEncryptionIdentifier
    private let personhoodOriginFactory: PersonhoodOriginFactoryProtocol
    private let candidateOriginFactory: CandidateOriginFactoryProtocol

    init(
        chain: ChainModel,
        candidateWallet: WalletManaging,
        scoreWallet: WalletManaging,
        encryptionIdentifier: Chat.OnChainEncryptionIdentifier,
        extrinsicSubmitMonitor: ExtrinsicSubmitMonitorFactoryProtocol,
        candidateOriginFactory: CandidateOriginFactoryProtocol,
        personhoodOriginFactory: PersonhoodOriginFactoryProtocol
    ) {
        self.chain = chain
        self.candidateWallet = candidateWallet
        self.scoreWallet = scoreWallet
        self.extrinsicSubmitMonitor = extrinsicSubmitMonitor
        self.encryptionIdentifier = encryptionIdentifier
        self.candidateOriginFactory = candidateOriginFactory
        self.personhoodOriginFactory = personhoodOriginFactory
    }
}

extension GameRegisterService: GameRegisterServicing {
    func registerForGame(
        with mode: GameRegisterMode,
        airdrop: GamePallet.AirdropVrfs?
    ) -> CompoundOperationWrapper<ExtrinsicMonitorSubmission> {
        switch mode {
        case let .player(isCredible):
            registerForGame(isCrediblePlayer: isCredible, airdrop: airdrop)
        case let .scoreAlias(alias):
            registerForGame(asScoreAlias: alias, airdrop: airdrop)
        }
    }

    func registerForGame(
        with invitation: Invitation,
        airdrop: GamePallet.AirdropVrfs?
    ) -> CompoundOperationWrapper<ExtrinsicMonitorSubmission> {
        registerForGame(invitation: invitation, airdrop: airdrop)
    }
}

private extension GameRegisterService {
    func airdropVariantDescription(_ airdrop: GamePallet.AirdropVrfs?) -> String {
        switch airdrop {
        case .none: "nil"
        case .account: "Account"
        case .alias: "Alias"
        }
    }

    func registerForGame(
        isCrediblePlayer: Bool,
        airdrop: GamePallet.AirdropVrfs?
    ) -> CompoundOperationWrapper<ExtrinsicMonitorSubmission> {
        Logger.shared.debug(
            "[GameDebug] submit SignUpWithAccount: isCredible=\(isCrediblePlayer) "
                + "airdrop=\(airdropVariantDescription(airdrop))"
        )
        do {
            let origin =
                if isCrediblePlayer {
                    try candidateOriginFactory.createSignedScoreAsParticipant(
                        for: candidateWallet,
                        chain: chain
                    )
                } else {
                    try candidateOriginFactory.createSignedOrigin(
                        for: candidateWallet,
                        chain: chain
                    )
                }

            return extrinsicSubmitMonitor.submitAndMonitorWrapper(
                extrinsicBuilderClosure: { [encryptionIdentifier] builder in
                    let call = try GamePallet.SignUpWithAccountCall(
                        identifierKey: encryptionIdentifier.scaleEncoded(),
                        airdrops: airdrop
                    )
                    return try builder.adding(call: call.runtimeCall())
                },
                origin: origin,
                params: ExtrinsicSubmissionParams(feeAssetId: nil, eventsMatcher: nil)
            )
        } catch {
            return .createWithError(error)
        }
    }

    func registerForGame(
        invitation: Invitation,
        airdrop: GamePallet.AirdropVrfs?
    ) -> CompoundOperationWrapper<ExtrinsicMonitorSubmission> {
        Logger.shared.debug(
            "[GameDebug] submit SignUpWithInvite: airdrop=\(airdropVariantDescription(airdrop))"
        )
        do {
            let inviterId = try invitation.issuer.toAccountId()
            let ticketId = try Data(hexString: invitation.publicKey)
            let signatureData = try Data(hexString: invitation.signature)

            let call = try GamePallet.SignUpWithInviteCall(
                identifierKey: encryptionIdentifier.scaleEncoded(),
                airdrops: airdrop
            )

            let origin = try candidateOriginFactory.createGameAsInvited(
                for: candidateWallet,
                chain: chain,
                inviter: inviterId,
                ticket: ticketId,
                signature: .sr25519(data: signatureData)
            )

            return extrinsicSubmitMonitor.submitAndMonitorWrapper(
                extrinsicBuilderClosure: { builder in
                    try builder.adding(call: call.runtimeCall())
                },
                origin: origin,
                params: ExtrinsicSubmissionParams(feeAssetId: nil, eventsMatcher: nil)
            )
        } catch {
            return .createWithError(error)
        }
    }

    func registerForGame(
        asScoreAlias alias: Data,
        airdrop: GamePallet.AirdropVrfs?
    ) -> CompoundOperationWrapper<ExtrinsicMonitorSubmission> {
        Logger.shared.debug(
            "[GameDebug] submit SignUpWithAlias: alias=\(alias.toHex(includePrefix: true)) "
                + "airdrop=\(airdropVariantDescription(airdrop))"
        )
        do {
            let origin = try personhoodOriginFactory.createAsPersonalAliasWithAccount(
                input: .init(
                    wallet: scoreWallet,
                    chain: chain,
                    context: Data(PalletContext.score.utf8),
                    blockHash: nil
                )
            )
            return extrinsicSubmitMonitor.submitAndMonitorWrapper(
                extrinsicBuilderClosure: { [weak self, scoreWallet, chain, encryptionIdentifier] builder in
                    guard let self else {
                        throw BaseOperationError.unexpectedDependentResult
                    }
                    let signature = try makeScoreAliasSignature(alias: alias)

                    let scoreAccountId = try scoreWallet.fetchAccount(for: chain).accountId
                    let call = try GamePallet.SignUpWithAliasCall(
                        identifierKey: encryptionIdentifier.scaleEncoded(),
                        statementAccount: scoreAccountId,
                        signature: signature,
                        airdrops: airdrop
                    )
                    return try builder.adding(call: call.runtimeCall())
                },
                origin: origin,
                params: ExtrinsicSubmissionParams(feeAssetId: nil, eventsMatcher: nil)
            )
        } catch {
            return .createWithError(error)
        }
    }

    func makeScoreAliasSignature(alias: Data) throws -> MultiSignature {
        let scoreAccount = try scoreWallet.fetchAccount(for: chain)
        let signer = DefaultSigningWrapper(secretProvider: scoreWallet)

        let prefix = Data("pop:game:stmt_account_for_alias:".utf8)
        let message = try (prefix + alias).blake2b32()
        let data = try signer.sign(
            message,
            context: .rawBytes(scoreAccount)
        )
        .rawData()

        switch scoreAccount.signatureType {
        case .sr25519:
            return .sr25519(data: data)
        case .ed25519:
            return .ed25519(data: data)
        case .ecdsa:
            return .ecdsa(data: data)
        }
    }
}
