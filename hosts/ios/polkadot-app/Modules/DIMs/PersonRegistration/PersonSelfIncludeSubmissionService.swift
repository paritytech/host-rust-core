import Foundation
import os
import ExtrinsicService
import SubstrateSdk
import Operation_iOS
import StructuredConcurrency
import CommonService
import ChainRegistry

protocol SelfIncludeSubmitting: AnyObject {
    func submitSelfInclude(callValidAt: UInt64) async throws
}

final class PersonSelfIncludeSubmissionService {
    let chain: ChainProtocol
    let operationFactory: PersonhoodRegistrationOperationMaking
    let extrinsicSubmissionFacade: ExtrinsicSubmissionMonitorFacadeProtocol
    let logger: LoggerProtocol

    private(set) var extrinsicSubmissionMonitor: ExtrinsicSubmitMonitorFactoryProtocol?

    private let inFlight = OSAllocatedUnfairLock<Task<Void, Error>?>(initialState: nil)

    init(
        chain: ChainProtocol,
        operationFactory: PersonhoodRegistrationOperationMaking,
        extrinsicSubmissionFacade: ExtrinsicSubmissionMonitorFacadeProtocol = ExtrinsicSubmissionMonitorFacade(
            chainRegistry: ChainRegistryFacade.sharedRegistry,
            substrateStorageFacade: SubstrateDataStorageFacade.shared,
            operationQueue: OperationManagerFacade.sharedDefaultQueue,
            logger: Logger.shared
        ),
        logger: LoggerProtocol = Logger.shared
    ) {
        self.chain = chain
        self.operationFactory = operationFactory
        self.extrinsicSubmissionFacade = extrinsicSubmissionFacade
        self.logger = logger
    }

    func setupExtrinsicSubmissionMonitor() -> ExtrinsicSubmitMonitorFactoryProtocol? {
        if let extrinsicSubmissionMonitor {
            return extrinsicSubmissionMonitor
        }

        do {
            let monitor = try extrinsicSubmissionFacade.createMonitorFactory(chain: chain)

            extrinsicSubmissionMonitor = monitor

            return monitor
        } catch {
            logger.error("Can't create extrinsic monitor: \(error)")

            return nil
        }
    }
}

extension PersonSelfIncludeSubmissionService: SelfIncludeSubmitting {
    enum SelfIncludeSubmissionError: Error {
        case missingExtrinsicMonitor
    }

    func submitSelfInclude(callValidAt: UInt64) async throws {
        let task = inFlight.withLock { existing -> Task<Void, Error> in
            if let existing {
                return existing
            }

            let task = Task {
                defer { inFlight.withLock { $0 = nil } }
                try await performSelfInclude(callValidAt: callValidAt)
            }

            existing = task

            return task
        }

        try await task.value
    }

    private func performSelfInclude(callValidAt: UInt64) async throws {
        guard let monitor = setupExtrinsicSubmissionMonitor() else {
            throw SelfIncludeSubmissionError.missingExtrinsicMonitor
        }

        let wrapper = operationFactory.selfInclude(
            callValidAt: callValidAt,
            extrinsicMonitor: monitor
        )

        _ = try await wrapper
            .asyncExecute()
            .ensureSuccess()
    }
}
