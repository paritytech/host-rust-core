import Foundation
import Operation_iOS
import Keystore_iOS
import BandersnatchApi
import ExtrinsicService
import SubstrateSdk
import KeyDerivation
import Individuality

protocol PersonhoodRegistrationOperationMaking {
    func registerPerson(
        candidateType: PersonRegistration.CandidateType,
        origin: ExtrinsicOriginDefining,
        extrinsicMonitor: ExtrinsicSubmitMonitorFactoryProtocol
    ) -> CompoundOperationWrapper<ExtrinsicMonitorSubmission>

    func selfInclude(
        callValidAt: UInt64,
        extrinsicMonitor: ExtrinsicSubmitMonitorFactoryProtocol
    ) -> CompoundOperationWrapper<ExtrinsicMonitorSubmission>
}

enum PersonhoodRegistrationOperationError: Error {
    case missingVouchersStoreManager
}

final class PersonhoodRegistrationOperationFactory {
    private let accountId: AccountId
    private let vrfManager: BandersnatchKeyManaging
    private let asMemberOriginFactory: AsMemberOriginCreating
    private let logger: LoggerProtocol

    init(
        accountId: AccountId,
        vrfManager: BandersnatchKeyManaging,
        asMemberOriginFactory: AsMemberOriginCreating = AsMemberOriginFactory(),
        logger: LoggerProtocol = Logger.shared
    ) {
        self.accountId = accountId
        self.vrfManager = vrfManager
        self.asMemberOriginFactory = asMemberOriginFactory
        self.logger = logger
    }
}

extension PersonhoodRegistrationOperationFactory: PersonhoodRegistrationOperationMaking {
    func registerPerson(
        candidateType: PersonRegistration.CandidateType,
        origin: any ExtrinsicOriginDefining,
        extrinsicMonitor: any ExtrinsicSubmitMonitorFactoryProtocol
    ) -> CompoundOperationWrapper<ExtrinsicMonitorSubmission> {
        switch candidateType {
        case let .proofOfInk(proofOfInkCandidateType):
            registerProofOfInkPerson(
                for: proofOfInkCandidateType,
                origin: origin,
                extrinsicMonitor: extrinsicMonitor
            )
        case let .game(isSuspended):
            registerGamePerson(
                isSuspended: isSuspended,
                origin: origin,
                extrinsicMonitor: extrinsicMonitor
            )
        }
    }

    func selfInclude(
        callValidAt: UInt64,
        extrinsicMonitor: any ExtrinsicSubmitMonitorFactoryProtocol
    ) -> CompoundOperationWrapper<ExtrinsicMonitorSubmission> {
        logger.debug("Trying to self-include, callValidAt=\(callValidAt)")

        let origin = asMemberOriginFactory.createSelfIncludeOrigin(vrfManager: vrfManager)

        return extrinsicMonitor.submitAndMonitorWrapper(
            extrinsicBuilderClosure: { [vrfManager] builder in
                let memberKey = try vrfManager.getMemberKey()
                let call = MembersPallet.SelfIncludeCall(
                    identifier: PeoplePallet.membersIdentifier,
                    member: memberKey,
                    callValidAt: callValidAt
                )
                return try builder.adding(call: call.runtimeCall())
            },
            origin: origin,
            params: ExtrinsicSubmissionParams(feeAssetId: nil, eventsMatcher: nil)
        )
    }
}

private extension PersonhoodRegistrationOperationFactory {
    func registerProofOfInkPerson(
        for candidateType: PersonRegistration.ProofOfInkCandidateType,
        origin: any ExtrinsicOriginDefining,
        extrinsicMonitor: any ExtrinsicSubmitMonitorFactoryProtocol
    ) -> CompoundOperationWrapper<ExtrinsicMonitorSubmission> {
        logger.debug("Trying to register as proof of ink person")

        return callRegister(
            for: candidateType,
            origin: origin,
            extrinsicMonitor: extrinsicMonitor
        )
    }

    func callRegister(
        for candidateType: PersonRegistration.ProofOfInkCandidateType,
        origin: ExtrinsicOriginDefining,
        extrinsicMonitor: ExtrinsicSubmitMonitorFactoryProtocol
    ) -> CompoundOperationWrapper<ExtrinsicMonitorSubmission> {
        switch candidateType {
        case .referred:
            callRegisterReferred(
                origin: origin,
                extrinsicMonitor: extrinsicMonitor
            )
        case .deposit,
             .invited:
            callRegisterNonReferred(
                origin: origin,
                extrinsicMonitor: extrinsicMonitor
            )
        }
    }

    func callRegisterReferred(
        origin: ExtrinsicOriginDefining,
        extrinsicMonitor: ExtrinsicSubmitMonitorFactoryProtocol
    ) -> CompoundOperationWrapper<ExtrinsicMonitorSubmission> {
        logger.debug("Trying to register as referred")

        return extrinsicMonitor.submitAndMonitorWrapper(
            extrinsicBuilderClosure: { [accountId, vrfManager] builder in
                let proof = try vrfManager.makeProofOfOwnership(accountId: accountId)
                let memberKey = try vrfManager.getMemberKey()
                let registerCall = ProofOfInkPallet.RegisterReferredPersonCall(
                    key: memberKey,
                    destination: accountId,
                    proofOfOwnership: proof
                )
                return try builder.adding(call: registerCall.runtimeCall())
            },
            origin: origin,
            params: ExtrinsicSubmissionParams(feeAssetId: nil, eventsMatcher: nil)
        )
    }

    func callRegisterNonReferred(
        origin: ExtrinsicOriginDefining,
        extrinsicMonitor: ExtrinsicSubmitMonitorFactoryProtocol
    ) -> CompoundOperationWrapper<ExtrinsicMonitorSubmission> {
        logger.debug("Trying to register as non-referred")

        return extrinsicMonitor.submitAndMonitorWrapper(
            extrinsicBuilderClosure: { [accountId, vrfManager] builder in
                let proof = try vrfManager.makeProofOfOwnership(accountId: accountId)
                let memberKey = try vrfManager.getMemberKey()
                let registerCall = ProofOfInkPallet.RegisterNonReferredPersonCall(
                    key: memberKey,
                    destination: accountId,
                    proofOfOwnership: proof
                )

                return try builder.adding(call: registerCall.runtimeCall())
            },
            origin: origin,
            params: ExtrinsicSubmissionParams(feeAssetId: nil, eventsMatcher: nil)
        )
    }

    func registerGamePerson(
        isSuspended: Bool,
        origin: ExtrinsicOriginDefining,
        extrinsicMonitor: ExtrinsicSubmitMonitorFactoryProtocol
    ) -> CompoundOperationWrapper<ExtrinsicMonitorSubmission> {
        logger.debug("Trying to register as game participant")

        return extrinsicMonitor.submitAndMonitorWrapper(
            extrinsicBuilderClosure: { [accountId, vrfManager] builder in
                let key: ScorePallet.KeyWithProof?
                if isSuspended {
                    key = nil
                } else {
                    let proof = try vrfManager.makeProofOfOwnership(accountId: accountId)
                    let memberKey = try vrfManager.getMemberKey()
                    key = ScorePallet.KeyWithProof(
                        key: memberKey,
                        proofOfOwnership: proof
                    )
                }
                let registerCall = ScorePallet.RegisterCall(key: key)
                return try builder.adding(call: registerCall.runtimeCall())
            },
            origin: origin,
            params: ExtrinsicSubmissionParams(feeAssetId: nil, eventsMatcher: nil)
        )
    }
}

private extension BandersnatchKeyManaging {
    func makeProofOfOwnership(
        accountId: AccountId
    ) throws -> Data {
        let prefix = Data("pop register using".utf8)
        let message = prefix + accountId
        return try sign(message)
    }
}
