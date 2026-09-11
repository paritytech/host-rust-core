import Foundation
import ExtrinsicService
import Operation_iOS
import SubstrateSdk
import Keystore_iOS
import Individuality
import KeyDerivation
import ChainRegistry

protocol FullUsernameClaimServicing {
    func claimUsername(
        _ username: Username,
        with availability: FullUsernameAvailability
    ) async throws
}

final class FullUsernameClaimService {
    private let chain: ChainModel
    private let registeredData: People.RegisteredData
    private let extrinsicSubmitMonitor: ExtrinsicSubmitMonitorFactoryProtocol
    private let extrinsicOriginFactory: PersonhoodOriginFactoryProtocol
    private let litePersonOriginFactory: ExtrinsicOriginDefiningFactoryProtocol
    private let liteWallet: WalletManaging
    private let resourcesWallet: WalletManaging
    private let logger: LoggerProtocol

    init(
        chain: ChainModel,
        registeredData: People.RegisteredData,
        extrinsicSubmitMonitor: ExtrinsicSubmitMonitorFactoryProtocol,
        extrinsicOriginFactory: PersonhoodOriginFactoryProtocol,
        litePersonOriginFactory: ExtrinsicOriginDefiningFactoryProtocol,
        liteWallet: WalletManaging,
        resourcesWallet: WalletManaging,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.chain = chain
        self.registeredData = registeredData
        self.extrinsicSubmitMonitor = extrinsicSubmitMonitor
        self.extrinsicOriginFactory = extrinsicOriginFactory
        self.litePersonOriginFactory = litePersonOriginFactory
        self.liteWallet = liteWallet
        self.resourcesWallet = resourcesWallet
        self.logger = logger
    }
}

extension FullUsernameClaimService: FullUsernameClaimServicing {
    func claimUsername(
        _ username: Username,
        with availability: FullUsernameAvailability
    ) async throws {
        switch availability {
        case .free:
            try await registerPerson(
                with: username,
                isReserved: false
            )
        case .reservedByUs:
            try await registerPerson(
                with: username,
                isReserved: true
            )
        case let .reclaimExpiredReservation(expiredAccountIds):
            try await removeExpiredReservations(
                for: username,
                expiredAccountIds: expiredAccountIds
            )
            try await registerPerson(
                with: username,
                isReserved: true
            )
        case .notAvailable:
            throw ClaimError.usernameNotAvailable
        }
    }
}

private extension FullUsernameClaimService {
    enum ClaimError: Error {
        case usernameNotAvailable
        case usernameEncodingFailed
        case missingAccountId
        case missingLiteAccount
    }

    func removeExpiredReservations(
        for username: Username,
        expiredAccountIds: [AccountId],
    ) async throws {
        logger.debug("Going to remove expired reservations for \(username.value)")

        guard let usernameData = username.value.data(using: .utf8) else {
            throw ClaimError.usernameEncodingFailed
        }

        let origin = try litePersonOriginFactory.extrinsicOriginDefiner(
            from: liteWallet,
            chain: chain
        )

        let wrapper = extrinsicSubmitMonitor.submitAndMonitorWrapper(
            extrinsicBuilderClosure: { builder in
                try expiredAccountIds.reduce(builder) { partialResult, accountId in
                    let call = ResourcesPallet.RemoveExpiredReservationCall(
                        username: usernameData,
                        account: accountId
                    )
                    return try partialResult.adding(call: call.runtimeCall())
                }
            },
            origin: origin,
            params: ExtrinsicSubmissionParams(feeAssetId: nil, eventsMatcher: nil)
        )

        let result = try await wrapper.asyncExecute()

        switch result.status {
        case let .success(successExtrinsic):
            logger.debug("Successful extrinsic: \(successExtrinsic)")
        case let .failure(failedExtrinsic):
            logger.error("Failed extrinsic: \(failedExtrinsic)")
            throw failedExtrinsic.error
        }
    }

    func registerPerson(
        with username: Username,
        isReserved: Bool
    ) async throws {
        logger.debug("Going to register person for \(username.value), isReserved: \(isReserved)")

        guard let usernameData = username.value.data(using: .utf8) else {
            throw ClaimError.usernameEncodingFailed
        }

        guard let liteAccountId = try? liteWallet.getRawPublicKey() else {
            throw ClaimError.missingAccountId
        }

        let origin = try extrinsicOriginFactory.createAsPersonalAliasWithAccount(
            input: .init(
                wallet: resourcesWallet,
                chain: chain,
                context: Data(PalletContext.resources.utf8),
                blockHash: nil
            )
        )

        let wrapper = extrinsicSubmitMonitor.submitAndMonitorWrapper(
            extrinsicBuilderClosure: { [weak self] builder in
                guard let self else {
                    throw BaseOperationError.unexpectedDependentResult
                }

                let liteIdentityProof = try makeLiteSignature()

                let usernameChoice: ResourcesPallet.UsernameChoice = isReserved
                    ? .reservation(username: BytesCodable(wrappedValue: usernameData))
                    : .standalone(username: BytesCodable(wrappedValue: usernameData))

                let call = ResourcesPallet.RegisterPersonCall(
                    linkedLiteIdentity: liteAccountId,
                    liteIdentityProof: liteIdentityProof,
                    usernameChoice: usernameChoice
                )

                return try builder.adding(call: call.runtimeCall())
            },
            origin: origin,
            params: ExtrinsicSubmissionParams(feeAssetId: nil, eventsMatcher: nil)
        )

        let result = try await wrapper.asyncExecute()

        switch result.status {
        case let .success(successExtrinsic):
            logger.debug("Successful extrinsic: \(successExtrinsic)")
        case let .failure(failedExtrinsic):
            logger.error("Failed extrinsic: \(failedExtrinsic.error)")
            throw failedExtrinsic.error
        }
    }

    func makeLiteSignature() throws -> MultiSignature {
        guard let account = try? liteWallet.fetchAccount(for: chain) else {
            throw ClaimError.missingLiteAccount
        }

        let signer = DefaultSigningWrapper(secretProvider: liteWallet)

        let data = try signer
            .sign(
                registeredData.resourcesAlias.alias,
                context: .rawBytes(account)
            )
            .rawData()

        switch account.signatureType {
        case .sr25519:
            return .sr25519(data: data)
        case .ed25519:
            return .ed25519(data: data)
        case .ecdsa:
            return .ecdsa(data: data)
        }
    }
}
