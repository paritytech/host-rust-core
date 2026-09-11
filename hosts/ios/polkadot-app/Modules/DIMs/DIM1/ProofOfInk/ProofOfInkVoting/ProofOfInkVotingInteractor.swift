import Foundation

final class ProofOfInkVotingInteractor {
    weak var presenter: ProofOfInkVotingInteractorOutputProtocol?
}

extension ProofOfInkVotingInteractor: ProofOfInkVotingInteractorInputProtocol {
    func setup() {}
}
