import Foundation
import CommonService

protocol DIM1EvidenceSubmissionFacadeProtocol {
    func setup()
    func throttle()
    func retry()
}

final class DIM1EvidenceSubmissionFacade {
    let coordinator: ApplicationServiceProtocol
    let submission: EvidenceSubmissionServiceProtocol

    init(coordinator: ApplicationServiceProtocol, submission: EvidenceSubmissionServiceProtocol) {
        self.coordinator = coordinator
        self.submission = submission
    }
}

extension DIM1EvidenceSubmissionFacade: DIM1EvidenceSubmissionFacadeProtocol {
    func setup() {
        coordinator.setup()
        submission.setup()
    }

    func throttle() {
        coordinator.throttle()
        submission.throttle()
    }

    func retry() {
        submission.retry()
    }
}
