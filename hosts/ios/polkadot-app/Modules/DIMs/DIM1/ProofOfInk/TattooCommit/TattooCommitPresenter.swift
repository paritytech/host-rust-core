import Foundation
import Foundation_iOS
import SubstrateSdk
import ExtrinsicService
import Individuality

@MainActor
final class TattooCommitPresenter {
    weak var view: TattooCommitViewProtocol?
    let viewModelFactory: TattooCommitViewModelFactoryProtocol
    let wireframe: TattooCommitWireframeProtocol
    let interactor: TattooCommitInteractorInputProtocol
    let choice: ProofOfInk.Choice
    let logger: LoggerProtocol

    private var blockTime: BlockTime?
    private var commitmentTimeout: BlockNumber?
    private var minJudgementDuration: OnChainHour?
    private var maxJudgementDuration: OnChainHour?
    private var tattooMetadata: TattooMetadata?

    init(
        interactor: TattooCommitInteractorInputProtocol,
        wireframe: TattooCommitWireframeProtocol,
        choice: ProofOfInk.Choice,
        viewModelFactory: TattooCommitViewModelFactoryProtocol,
        logger: LoggerProtocol
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
        self.choice = choice
        self.viewModelFactory = viewModelFactory
        self.logger = logger
    }

    private func provideViewModel() {
        guard let metadataInfo = tattooMetadata?.metadata else {
            return
        }

        // TODO: Decide about Tattoo sizes
        let dataModel = TattooCommitModel(
            name: metadataInfo.name,
            description: metadataInfo.description ?? "",
            tattooSize: 25,
            tattooMaxSize: 50,
            evidenceLowerTimeframe: minJudgementDuration,
            evidenceUpperTimeframe: maxJudgementDuration
        )

        view?.didReceiveDescription(
            viewModel: viewModelFactory.createListViewModel(
                from: dataModel,
                choice: choice
            )
        )
    }

    private func handleTattooCommit(error: Error) {
        // TODO: Specifically detect AlreadyTaken error
        if case .module = error as? Substrate.DispatchCallError {
            wireframe.present(
                viewModel: .init(
                    title: String(localized: .Common.error),
                    message: String(localized: .Tattoo.commitAlreadyReservedError),
                    actions: [
                        .init(
                            title: String(localized: .Common.close),
                            handler: { [weak self] in
                                self?.wireframe.cancel(view: self?.view)
                            }
                        )
                    ]
                ),
                style: .alert,
                from: view
            )
        } else {
            wireframe.present(
                message: String(localized: .Tattoo.commitFailedError),
                title: String(localized: .Common.error),
                closeAction: String(localized: .Common.close),
                from: view
            )
        }
    }
}

extension TattooCommitPresenter: TattooCommitPresenterProtocol {
    func setup() {
        provideViewModel()
        interactor.setup()
    }

    func proceed() {
        guard blockTime != nil, commitmentTimeout != nil else {
            return
        }

        let model = TattooConfirmModel(
            confirmClosure: { [weak self] in
                self?.view?.didStartLoading()
                self?.interactor.confirm()
            },
            cancelClosure: {}
        )
        wireframe.confirm(on: view, model: model)
    }
}

extension TattooCommitPresenter: TattooCommitInteractorOutputProtocol {
    func didReceive(blockTime: BlockTime) {
        logger.debug("Block time: \(blockTime)")

        self.blockTime = blockTime
    }

    func didReceive(commitmentTimeout: BlockNumber) {
        logger.debug("Commitment timeout: \(commitmentTimeout)")

        self.commitmentTimeout = commitmentTimeout
    }

    func didReceive(minJudgementDuration: OnChainHour) {
        logger.debug("Min Judgement: \(minJudgementDuration)")

        self.minJudgementDuration = minJudgementDuration

        provideViewModel()
    }

    func didReceive(maxJudgementDuration: OnChainHour) {
        logger.debug("Max Judgement: \(maxJudgementDuration)")

        self.maxJudgementDuration = maxJudgementDuration

        provideViewModel()
    }

    func didConfirm(with txHash: String) {
        logger.debug("Commit sent: \(txHash)")

        wireframe.complete(view: view)
    }

    func didReceiveTattoo(metadata: TattooMetadata) {
        tattooMetadata = metadata

        provideViewModel()
    }

    func didReceive(error: TattooCommitInteractorError) {
        logger.error("Error: \(error)")

        switch error {
        case .blockTimeServiceError:
            wireframe.presentRequestStatus(on: view) { [weak self] in
                self?.interactor.retrySubscription()
            }
        case .commitmentTimeout:
            wireframe.presentRequestStatus(on: view) { [weak self] in
                self?.interactor.retryCommitmentTimeout()
            }
        case .judgementDuration:
            wireframe.presentRequestStatus(on: view) { [weak self] in
                self?.interactor.retryJudgementDuration()
            }
        case .tattooMetadataFailed:
            wireframe.presentRequestStatus(on: view) { [weak self] in
                self?.interactor.retryTattooMetadata()
            }
        case let .confirmationFailed(internalError):
            view?.didStopLoading()

            handleTattooCommit(error: internalError)
        case .commitAvailabilityFailed:
            view?.didStopLoading()

            wireframe.present(
                message: String(localized: .Tattoo.commitBusyError),
                title: String(localized: .Common.error),
                closeAction: String(localized: .Common.close),
                from: view
            )
        }
    }
}
