import UIKit
import PolkadotUI
import FoundationExt

final class ProofOfInkVotingViewController: UIViewController, ViewHolder {
    typealias RootViewType = ProofOfInkVotingLayout

    let presenter: ProofOfInkVotingPresenterProtocol

    init(presenter: ProofOfInkVotingPresenterProtocol) {
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = ProofOfInkVotingLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        rootView.setParentViewController(self)
        rootView.delegate = self
        presenter.setup()
    }
}

// MARK: - ProofOfInkVotingViewProtocol

extension ProofOfInkVotingViewController: ProofOfInkVotingViewProtocol {
    func didReceive(viewModel: ProofOfInkVotingViewModel) {
        rootView.bind(viewModel: viewModel)
    }
}

// MARK: - ProofOfInkVotingLayoutDelegate

extension ProofOfInkVotingViewController: ProofOfInkVotingLayoutDelegate {
    func proofOfInkVotingLayoutDidTapClose(_: ProofOfInkVotingLayout) {
        presenter.close()
    }

    func proofOfInkVotingLayoutDidTapReport(_: ProofOfInkVotingLayout) {
        presenter.report()
    }

    func proofOfInkVotingLayoutDidVote(_: ProofOfInkVotingLayout, result: ProofOfInkVotingLayout.VoteResult) {
        presenter.vote(result: result)
    }
}
