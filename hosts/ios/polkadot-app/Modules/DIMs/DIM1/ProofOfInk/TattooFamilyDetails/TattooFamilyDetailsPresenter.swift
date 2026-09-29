import Foundation
import Individuality

@MainActor
final class TattooFamilyDetailsPresenter {
    weak var view: TattooFamilyDetailsViewProtocol?
    private let wireframe: TattooFamilyDetailsWireframeProtocol
    private let interactor: TattooFamilyDetailsInteractorInputProtocol
    private let viewModelFactory: TattooFamilyViewModelFactoryProtocol
    private let tattooFamilies: [ProofOfInk.Collection]
    private let tattooParams: TattooGenerationParams
    private let logger: LoggerProtocol

    private let sectionMetadata: TattooSectionMetadata
    private var reservedDesigns: ProofOfInkPallet.ReservedDesignsResult?

    init(
        sectionMetadata: TattooSectionMetadata,
        tattooFamilies: [ProofOfInk.Collection],
        interactor: TattooFamilyDetailsInteractorInputProtocol,
        wireframe: TattooFamilyDetailsWireframeProtocol,
        tattooParams: TattooGenerationParams,
        viewModelFactory: TattooFamilyViewModelFactoryProtocol,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.sectionMetadata = sectionMetadata
        self.tattooFamilies = tattooFamilies
        self.interactor = interactor
        self.wireframe = wireframe
        self.tattooParams = tattooParams
        self.viewModelFactory = viewModelFactory
        self.logger = logger
    }
}

extension TattooFamilyDetailsPresenter: TattooFamilyDetailsPresenterProtocol {
    func setup() {
        provideViewModel()
        interactor.setup()
    }

    func updateOnAppear() {
        interactor.retryReserved()
    }

    func perform(_ action: TattooFamilyDetailsAction) {
        switch action {
        case let .selectTattoo(choice):
            wireframe.showTattooCommit(from: view, choice: choice)
        }
    }
}

extension TattooFamilyDetailsPresenter: TattooFamilyDetailsInteractorOutputProtocol {
    func didReceiveReservedDesigns(_ reservedDesigns: ProofOfInkPallet.ReservedDesignsResult) {
        logger.debug("Reserved designs: \(reservedDesigns)")

        self.reservedDesigns = reservedDesigns

        provideViewModel()
    }

    func didReceiveError(_ error: TattooFamilyDetailsInteractorError) {
        logger.error("Did receive error: \(error)")

        switch error {
        case .reservedFailed:
            wireframe.presentRequestStatus(on: view) { [weak self] in
                self?.interactor.retryReserved()
            }
        }
    }
}

private extension TattooFamilyDetailsPresenter {
    func provideViewModel() {
        if let reservedDesigns {
            view?.didReceive(
                viewModelFactory.createViewModel(
                    from: tattooFamilies,
                    reservedDesigns: reservedDesigns,
                    params: tattooParams,
                    texts: sectionMetadata.texts
                )
            )
        } else {
            view?.didReceive(.init(items: []))
        }
    }
}
