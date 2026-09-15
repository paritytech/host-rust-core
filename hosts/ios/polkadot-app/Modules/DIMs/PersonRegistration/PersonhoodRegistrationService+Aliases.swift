import Foundation
import ExtrinsicService
import Operation_iOS
import SubstrateSdk
import Individuality
import KeyDerivation
import SubstrateOperation

extension PersonhoodRegistrationService {
    func checkAliasesCreation(with remoteState: PersonRegistration.RemoteState) {
        checkAliasCreationState(
            remoteState.mobRuleAlias,
            input: .init(
                wallet: mobRuleWallet,
                creationState: .requiresMobRule,
                progress: .submittingMobRuleAlias,
                context: PalletContext.mobRule
            ),
            remoteState: remoteState
        )

        checkAliasCreationState(
            remoteState.scoreAlias,
            input: .init(
                wallet: scoreWallet,
                creationState: .requiresScore,
                progress: .submittingScoreAlias,
                context: PalletContext.score
            ),
            remoteState: remoteState
        )

        checkAliasCreationState(
            remoteState.resourcesAlias,
            input: .init(
                wallet: resourcesWallet,
                creationState: .requiresResources,
                progress: .submittingResourcesAlias,
                context: PalletContext.resources
            ),
            remoteState: remoteState
        )
    }
}

// MARK: - State

private extension PersonhoodRegistrationService {
    struct AliasCreationInput {
        let wallet: WalletManaging
        let creationState: PersonRegistration.RemoteState.AliasCreationState
        let progress: PersonRegistration.Progress
        let context: String
    }

    func checkAliasCreationState(
        _ alias: PeoplePallet.RevisedContextualAlias?,
        input: AliasCreationInput,
        remoteState: PersonRegistration.RemoteState
    ) {
        checkStartAliasCreation(
            with: input,
            remoteState: remoteState
        )
        checkFinishCreatingAlias(
            alias,
            remoteState: remoteState,
            progress: input.progress
        )
    }

    func checkStartAliasCreation(
        with input: AliasCreationInput,
        remoteState: PersonRegistration.RemoteState
    ) {
        guard
            localState.progress.isIdle,
            remoteState.isNotSuspendedPerson,
            remoteState.hasPersonalIdAccount,
            remoteState.aliasCreationState == input.creationState
        else {
            return
        }

        guard
            let chain = chainRegistry.getChain(for: chain.chainId),
            let accountId = try? input.wallet.fetchAccount(for: chain).accountId
        else {
            logger.error("Missing alias account id")
            return
        }

        logger.debug("Will start alias submission")

        submitAliasCreation(
            remoteState: remoteState,
            accountId: accountId,
            context: Data(input.context.utf8),
            progress: input.progress
        )
    }

    func checkFinishCreatingAlias(
        _ alias: PeoplePallet.RevisedContextualAlias?,
        remoteState: PersonRegistration.RemoteState,
        progress: PersonRegistration.Progress
    ) {
        guard
            localState.progress == progress,
            remoteState.hasRelevantAlias(alias: alias)
        else {
            return
        }

        updateLocalState(progress: .idle)
    }
}

// MARK: - Submitting

private extension PersonhoodRegistrationService {
    func submitAliasCreation(
        remoteState: PersonRegistration.RemoteState,
        accountId: AccountId,
        context: Data,
        progress: PersonRegistration.Progress
    ) {
        guard let ringIndex = remoteState.memberRingPosition?.ringIndex else {
            logger.error("Missing ring data")
            return
        }

        guard let origin = try? personhoodOriginFactory.createAsPersonalAliasWithProof(
            input: .init(
                collectionId: PeoplePallet.membersIdentifier,
                ringIndex: ringIndex,
                context: context,
                blockHash: remoteState.blockHash
            )
        ) else {
            logger.error("Can't create personal alias with proof origin")
            return
        }

        guard let extrinsicSubmissionMonitor = setupExtrinsicSubmissionMonitor() else {
            return
        }

        updateLocalState(progress: progress)

        executeSubmitAlias(
            extrinsicSubmissionMonitor: extrinsicSubmissionMonitor,
            origin: origin,
            accountId: accountId
        )
    }

    func executeSubmitAlias(
        extrinsicSubmissionMonitor: ExtrinsicSubmitMonitorFactoryProtocol,
        origin: ExtrinsicOriginDefining,
        accountId: AccountId
    ) {
        let blockNumberWrapper = blockNumberOperationFactory.bestBlockWrapper(for: chain.chainId)

        let submissionWrapper = extrinsicSubmissionMonitor.submitAndMonitorWrapper(
            extrinsicBuilderClosure: { builder in
                let blockNumber = try blockNumberWrapper.targetOperation.extractNoCancellableResultData()
                let call = PeoplePallet.SetAliasAccountCall(account: accountId, callValidAt: blockNumber)
                return try builder.adding(call: call.runtimeCall())
            },
            origin: origin,
            params: .init(feeAssetId: nil, eventsMatcher: nil)
        )

        submissionWrapper.addDependency(wrapper: blockNumberWrapper)

        let wrapper = submissionWrapper.insertingHead(operations: blockNumberWrapper.allOperations)

        execute(
            wrapper: wrapper,
            inOperationQueue: operationQueue,
            runningCallbackIn: syncQueue
        ) { [weak self] result in
            do {
                let executionResult = try result.get()

                switch executionResult.status {
                case .success:
                    self?.logger.debug("Alias creation successfully executed")
                case let .failure(dispatchError):
                    throw dispatchError.error
                }
            } catch {
                self?.logger.error("Alias creation failed \(error)")
                self?.updateLocalState(error: .failedCreatingAlias)
            }
        }
    }
}

// MARK: - Helpers

private extension PersonRegistration.RemoteState {
    enum AliasCreationState {
        case notReady
        case requiresMobRule
        case requiresIdentity
        case requiresScore
        case requiresResources
        case done
    }

    var aliasCreationState: AliasCreationState {
        guard let memberRingPosition else {
            return .notReady
        }

        if mobRuleAlias.isRelevant(accordingTo: memberRingPosition),
           scoreAlias.isRelevant(accordingTo: memberRingPosition),
           resourcesAlias.isRelevant(accordingTo: memberRingPosition) {
            return .done
        }

        var canSubmitAlias = false

        if let keysStatus, keysStatus.includesKey(from: memberRingPosition) {
            canSubmitAlias = true
        }

        if !mobRuleAlias.isRelevant(accordingTo: memberRingPosition) {
            return canSubmitAlias ? .requiresMobRule : .notReady
        }

        if !scoreAlias.isRelevant(accordingTo: memberRingPosition) {
            return canSubmitAlias ? .requiresScore : .notReady
        }

        if !resourcesAlias.isRelevant(accordingTo: memberRingPosition) {
            return canSubmitAlias ? .requiresResources : .notReady
        }

        return .done
    }
}
