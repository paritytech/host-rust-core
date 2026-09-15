import SubstrateSdk
import Individuality
import UIKitExt

protocol TattooCommitViewProtocol: ControllerBackedProtocol {
    func didReceiveDescription(viewModel: TattooCommitListViewModel)
    func didStartLoading()
    func didStopLoading()
}

@MainActor
protocol TattooCommitPresenterProtocol: AnyObject {
    func setup()
    func proceed()
}

protocol TattooCommitInteractorInputProtocol: AnyObject {
    func setup()
    func retrySubscription()
    func retryCommitmentTimeout()
    func retryJudgementDuration()
    func retryTattooMetadata()
    func confirm()
}

@MainActor
protocol TattooCommitInteractorOutputProtocol: AnyObject {
    func didReceive(blockTime: BlockTime)
    func didReceive(commitmentTimeout: BlockNumber)
    func didReceive(minJudgementDuration: OnChainHour)
    func didReceive(maxJudgementDuration: OnChainHour)
    func didReceiveTattoo(metadata: TattooMetadata)
    func didReceive(error: TattooCommitInteractorError)
    func didConfirm(with txHash: String)
}

@MainActor
protocol TattooCommitWireframeProtocol: AlertPresentable, ErrorPresentable, CommonRetryable {
    func confirm(on view: TattooCommitViewProtocol?, model: TattooConfirmModel)
    func cancel(view: TattooCommitViewProtocol?)
    func complete(view: TattooCommitViewProtocol?)
}
