import Foundation
import ExtrinsicService
import SubstrateSdk
import Operation_iOS
import Keystore_iOS
import KeyDerivation
import Individuality
import ChainRegistry

protocol PersonhoodOriginFactoryProtocol: ExtrinsicOriginFactoryProtocol {
    func createAsPersonalAliasWithProof(
        input: AsPersonAliasWithProofInput
    ) throws -> ExtrinsicOriginDefining

    func createAsPersonalIdentityWithProof(
        for model: PeoplePallet.AsPersonTxExtension.AsPersonalIdentityWithProofUsability
    ) throws -> ExtrinsicOriginDefining

    func createAsPersonalAliasWithAccount(
        input: AsPersonAliasWithAccountInput
    ) throws -> ExtrinsicOriginDefining

    func createAsPersonalIdentityWithAccount(
        from wallet: WalletManaging,
        chain: ChainProtocol
    ) throws -> ExtrinsicOriginDefining
}

final class PersonhoodOriginFactory: ExtrinsicOriginFactory {
    let vrfManager: BandersnatchKeyManaging

    init(
        vrfManager: BandersnatchKeyManaging,
        chainRegistry: ChainRegistryProtocol,
        operationQueue: OperationQueue,
        logger: LoggerProtocol
    ) {
        self.vrfManager = vrfManager

        super.init(
            chainRegistry: chainRegistry,
            operationQueue: operationQueue,
            logger: logger
        )
    }
}

extension PersonhoodOriginFactory: PersonhoodOriginFactoryProtocol {
    func createAsPersonalAliasWithProof(
        input: AsPersonAliasWithProofInput
    ) throws -> ExtrinsicOriginDefining {
        let connection = try chainRegistry.getConnectionOrError(for: AppConfig.Chains.usernameChain)
        let runtimeProvider = try chainRegistry.getRuntimeProviderOrError(for: AppConfig.Chains.usernameChain)

        return ExtrinsicCompoundOrigin(
            children: [
                RestrictsOriginDefinition(enabled: true),
                AsPersonalAliasWithProofOrigin(
                    input: input,
                    proofParamsFetcher: MembershipProofParamsFetcher(
                        connection: connection,
                        runtimeCodingService: runtimeProvider
                    ),
                    vrfManager: vrfManager,
                    operationQueue: operationQueue
                )
            ]
        )
    }

    func createAsPersonalIdentityWithProof(
        for model: PeoplePallet.AsPersonTxExtension.AsPersonalIdentityWithProofUsability
    ) throws -> ExtrinsicOriginDefining {
        ExtrinsicCompoundOrigin(
            children: [
                RestrictsOriginDefinition(enabled: true),
                AsPersonalIdentityOrigin(model: model)
            ]
        )
    }

    func createAsPersonalAliasWithAccount(
        input: AsPersonAliasWithAccountInput
    ) throws -> ExtrinsicOriginDefining {
        let connection = try chainRegistry.getConnectionOrError(for: AppConfig.Chains.usernameChain)
        let runtimeProvider = try chainRegistry.getRuntimeProviderOrError(for: AppConfig.Chains.usernameChain)

        let accountOrigin = try createAccountOrigin(for: input.wallet, chain: input.chain)
        let aliasOrigin = AsPersonalAliasWithAccountDefinition(
            input: input,
            aliasRevisionFactory: AliasRevisionOperationFactory(
                connection: connection,
                runtimeProvider: runtimeProvider,
                collectionIdentifier: PeoplePallet.membersIdentifier,
                operationQueue: operationQueue
            ),
            proofParamsFetcher: MembershipProofParamsFetcher(
                connection: connection,
                runtimeCodingService: runtimeProvider
            ),
            vrfManager: vrfManager,
            operationQueue: operationQueue
        )
        let signedOrigin = try createSigningByAccountOrigin(for: input.wallet, chain: input.chain)
        let restrictionOrigin = RestrictsOriginDefinition(enabled: true)

        return ExtrinsicCompoundOrigin(children: [accountOrigin, restrictionOrigin, aliasOrigin, signedOrigin])
    }

    func createAsPersonalIdentityWithAccount(
        from wallet: WalletManaging,
        chain: ChainProtocol
    ) throws -> ExtrinsicOriginDefining {
        let accountOrigin = try createAccountOrigin(for: wallet, chain: chain)
        let personIdentityOrigin = AsPersonalIdentityWithAccountOrigin()
        let signedOrigin = try createSigningByAccountOrigin(for: wallet, chain: chain)
        let restrictionOrigin = RestrictsOriginDefinition(enabled: true)

        return ExtrinsicCompoundOrigin(
            children: [accountOrigin, restrictionOrigin, personIdentityOrigin, signedOrigin]
        )
    }
}
