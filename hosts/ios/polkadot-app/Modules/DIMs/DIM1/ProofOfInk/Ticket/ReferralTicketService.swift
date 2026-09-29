import BandersnatchApi
import Foundation
import SubstrateSdk
import NovaCrypto
import Keystore_iOS
import Operation_iOS
import ExtrinsicService
import Individuality
import KeyDerivation

protocol ReferralTicketServicing: AnyObject {
    func submitNewReferral(
        ticket: ProofOfInkPallet.ReferralTicket,
        dispatchIn queue: DispatchQueue,
        completion: @escaping (Result<Void, Error>) -> Void
    )

    func cancelReferral(
        dispatchIn queue: DispatchQueue,
        completion: @escaping (Result<Void, Error>) -> Void
    )
}

final class ReferralTicketService {
    private let walletRepo: WalletManagerRepositoryProtocol
    private let chain: ChainProtocol
    private let extrinsicSubmitFacade: ExtrinsicSubmissionMonitorFacadeProtocol
    private let extrinsicOriginFactory: ExtrinsicOriginDefiningFactoryProtocol
    private let operationQueue: OperationQueue
    private let logger: LoggerProtocol

    private var submissionFactory: ExtrinsicSubmitMonitorFactoryProtocol?

    init(
        walletRepo: WalletManagerRepositoryProtocol = .shared,
        chain: ChainProtocol,
        extrinsicSubmitFacade: ExtrinsicSubmissionMonitorFacadeProtocol,
        extrinsicOriginFactory: ExtrinsicOriginDefiningFactoryProtocol, // AsPersonalIdentityWithAccountOriginFactory
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.walletRepo = walletRepo
        self.chain = chain
        self.extrinsicSubmitFacade = extrinsicSubmitFacade
        self.extrinsicOriginFactory = extrinsicOriginFactory
        self.operationQueue = operationQueue
        self.logger = logger
    }
}

private extension ReferralTicketService {
    func setupSubmissionFactory() throws -> ExtrinsicSubmitMonitorFactoryProtocol {
        if let submissionFactory {
            return submissionFactory
        }

        let factory = try extrinsicSubmitFacade.createMonitorFactory(chain: chain)
        submissionFactory = factory

        return factory
    }

    func submitExtrinsicAsPersonalIdentity(
        runtimeCallBuilder: @escaping () -> RuntimeCall<some Codable>,
        dispatchIn queue: DispatchQueue,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        do {
            let submissionFactory = try setupSubmissionFactory()

            // was createAsPersonalIdentityWithAccount
            let extrinsicOrigin = try extrinsicOriginFactory.extrinsicOriginDefiner(
                from: walletRepo.candidate(),
                chain: chain
            )

            let builderClosure: ExtrinsicBuilderClosure = { builder in
                let call = runtimeCallBuilder()
                return try builder.adding(call: call)
            }

            let wrapper = submissionFactory.submitAndMonitorWrapper(
                extrinsicBuilderClosure: builderClosure,
                origin: extrinsicOrigin,
                params: ExtrinsicSubmissionParams(feeAssetId: nil, eventsMatcher: nil)
            )

            execute(
                wrapper: wrapper,
                inOperationQueue: operationQueue,
                runningCallbackIn: queue
            ) { result in
                do {
                    let executionResult = try result.get()

                    switch executionResult.status {
                    case .success:
                        completion(.success(()))
                    case let .failure(dispatchError):
                        throw dispatchError.error
                    }
                } catch {
                    completion(.failure(error))
                }
            }
        } catch {
            dispatchInQueueWhenPossible(queue) {
                completion(.failure(error))
            }
        }
    }
}

extension ReferralTicketService: ReferralTicketServicing {
    func submitNewReferral(
        ticket: ProofOfInkPallet.ReferralTicket,
        dispatchIn queue: DispatchQueue,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        submitExtrinsicAsPersonalIdentity(
            runtimeCallBuilder: { ProofOfInkPallet.SetReferralTicketCall(ticket: ticket.ticket).runtimeCall() },
            dispatchIn: queue,
            completion: completion
        )
    }

    func cancelReferral(
        dispatchIn queue: DispatchQueue,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        submitExtrinsicAsPersonalIdentity(
            runtimeCallBuilder: { ProofOfInkPallet.CancelReferralTicketCall().runtimeCall() },
            dispatchIn: queue,
            completion: completion
        )
    }
}
