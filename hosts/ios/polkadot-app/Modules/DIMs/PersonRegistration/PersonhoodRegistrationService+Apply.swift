import Foundation
import Operation_iOS
import ExtrinsicService
import SubstrateSdk
import StructuredConcurrency
import Individuality
import SubstrateOperation
import KeyDerivation

extension PersonhoodRegistrationService {
    func applyState() {
        guard !localState.progress.isNotTriggered else {
            return
        }

        guard let remoteState else {
            return
        }

        logger.debug("Remote state: \(remoteState)")
        logger.debug("Local state: \(localState)")

        // we don't have manual retry and should retry automatically
        // to do this we ensure that we run extrinsics in a proper state
        // in which they should succeed under normal network conditions
        resetLocalStateIfError()

        checkStartRegisterAsPerson(remoteState: remoteState)
        checkFinishRegisterAsPerson(remoteState: remoteState)

        checkStartSelfInclude(remoteState: remoteState)
        checkFinishSelfInclude(remoteState: remoteState)

        checkSetPersonalIdAccount(remoteState: remoteState)
        checkFinishSetPersonalIdAccount(remoteState: remoteState)

        checkAliasesCreation(with: remoteState)
    }
}

private extension PersonhoodRegistrationService {
    func checkStartRegisterAsPerson(remoteState: PersonRegistration.RemoteState) {
        guard
            let registrableCandidateType = remoteState.registrableCandidateType(),
            !remoteState.isNotSuspendedPerson,
            localState.progress.isIdle
        else {
            return
        }

        logger.debug("Registering with candidate type: \(registrableCandidateType)")

        guard let extrinsicSubmissionMonitor = setupExtrinsicSubmissionMonitor() else {
            logger.error("Can't create extrinsic submission monitor")
            return
        }

        guard
            let origin = try? candidateOriginFactory.createPersonRegistrationDefinition(
                for: registrableCandidateType,
                wallet: candidateWallet,
                chain: chain
            )
        else {
            logger.error("Can't create origin")
            return
        }

        updateLocalState(progress: .submittingRegisterPerson)

        execute(
            wrapper: operationFactory.registerPerson(
                candidateType: registrableCandidateType,
                origin: origin,
                extrinsicMonitor: extrinsicSubmissionMonitor
            ),
            inOperationQueue: operationQueue,
            runningCallbackIn: syncQueue
        ) { [weak self] result in
            do {
                let executionResult = try result.get()

                switch executionResult.status {
                case .success:
                    self?.logger.debug("Person registration successfully executed")
                case let .failure(dispatchError):
                    self?.logger.error("Person registration failed onchain: \(dispatchError)")
                    self?.updateLocalState(error: .failedPersonRegistration)
                }
            } catch {
                self?.logger.error("Person registration failed: \(error)")
                self?.updateLocalState(error: .failedPersonRegistration)
            }
        }
    }

    func checkSetPersonalIdAccount(remoteState: PersonRegistration.RemoteState) {
        guard
            localState.progress.isIdle,
            remoteState.isNotSuspendedPerson,
            remoteState.hasPersonalRecord,
            !remoteState.hasPersonalIdAccount
        else {
            return
        }

        guard
            let chain = chainRegistry.getChain(for: chain.chainId),
            let accountId = try? candidateWallet.fetchAccount(for: chain).accountId
        else {
            logger.error("Missing personal id account")
            return
        }

        logger.debug("Will start setting personal id account")

        submitPersonalIdAccount(
            remoteState: remoteState,
            accountId: accountId,
            progress: .submittingPersonalIdAccount
        )
    }

    func checkFinishRegisterAsPerson(
        remoteState: PersonRegistration.RemoteState
    ) {
        guard
            localState.progress.isRegisteringPerson,
            remoteState.isNotSuspendedPerson
        else {
            return
        }

        updateLocalState(progress: .idle)
    }

    func checkFinishSetPersonalIdAccount(
        remoteState: PersonRegistration.RemoteState
    ) {
        guard
            localState.progress.isSubmittingPersonalIdAccount,
            remoteState.hasPersonalIdAccount
        else {
            return
        }

        updateLocalState(progress: .idle)
    }

    func checkStartSelfInclude(remoteState: PersonRegistration.RemoteState) {
        guard localState.progress.isIdle else {
            return
        }

        let callValidAt: UInt64
        switch remoteState.selfIncludeEligibility {
        case .unavailable:
            logger.debug("Self-inclusion not enabled for this collection")
            return
        case .notOnboarding,
             .waiting:
            return
        case let .eligible(timestamp):
            callValidAt = timestamp
        }

        logger.debug("Will start self-include, callValidAt=\(callValidAt)")
        updateLocalState(progress: .submittingSelfInclude)
        submitSelfInclude(callValidAt: callValidAt)
    }

    func checkFinishSelfInclude(remoteState: PersonRegistration.RemoteState) {
        guard
            localState.progress.isSubmittingSelfInclude,
            remoteState.memberRingPosition?.isIncluded == true
        else {
            return
        }
        updateLocalState(progress: .idle)
    }

    func submitSelfInclude(callValidAt: UInt64) {
        Task {
            do {
                try await selfIncludeSubmissionService.submitSelfInclude(callValidAt: callValidAt)
                logger.debug("Self-include successfully executed, waiting for on chain update")
            } catch {
                logger.error("Self-include failed: \(error)")
                syncQueue.async { [weak self] in
                    self?.updateLocalState(error: .failedSelfInclude)
                }
            }
        }
    }

    func submitPersonalIdAccount(
        remoteState: PersonRegistration.RemoteState,
        accountId: AccountId,
        progress: PersonRegistration.Progress
    ) {
        guard let personalId = remoteState.personalId else {
            logger.error("Missing personal id")
            return
        }

        guard let origin = try? personhoodOriginFactory.createAsPersonalIdentityWithProof(
            for: .init(
                vrfManager: vrfManager,
                personalId: personalId
            )
        ) else {
            logger.error("Can't set personal id account with proof origin")
            return
        }

        guard let extrinsicSubmissionMonitor = setupExtrinsicSubmissionMonitor() else {
            return
        }

        updateLocalState(progress: progress)

        let blockNumberWrapper = blockNumberOperationFactory.bestBlockWrapper(for: chain.chainId)

        let submissionWrapper = extrinsicSubmissionMonitor.submitAndMonitorWrapper(
            extrinsicBuilderClosure: { builder in
                let blockNumber = try blockNumberWrapper.targetOperation.extractNoCancellableResultData()
                let call = PeoplePallet.SetPersonalIdAccount(account: accountId, callValidAt: blockNumber)
                return try builder.adding(call: call.runtimeCall())
            },
            origin: origin,
            params: ExtrinsicSubmissionParams(feeAssetId: nil, eventsMatcher: nil)
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
                    self?.logger.debug("Personal id account set successfully executed")
                case let .failure(dispatchError):
                    throw dispatchError.error
                }
            } catch {
                self?.logger.error("Personal id account set failed \(error)")
                self?.updateLocalState(error: .failedSettingPersonalIdAccount)
            }
        }
    }
}

extension PersonhoodRegistrationService: PersonSelfIncludeBackgroundServiceDelegate {
    var selfIncludeEarliestBeginDate: Date? {
        guard let remoteState else { return nil }

        switch remoteState.selfIncludeEligibility {
        case .unavailable,
             .notOnboarding:
            return nil
        case .eligible:
            return Date()
        case .waiting:
            guard
                let queuedAt = remoteState.memberRingPosition?.onboardingQueuedAt,
                let delay = remoteState.collectionInfo?.selfInclusionDelay
            else {
                return nil
            }
            // Schedule slightly after the on-chain threshold so device/chain
            // clock drift can't push the submission into `SelfInclusionTooEarly`.
            let bufferSeconds: TimeInterval = 20

            let eligibilityEpoch = TimeInterval(queuedAt + delay) + bufferSeconds
            return Date(timeIntervalSince1970: eligibilityEpoch)
        }
    }
}
