import Foundation
import UIKit
import AVFoundation
import Foundation_iOS
import Individuality

@MainActor
final class TattooEvidencePhotoPresenter {
    weak var view: TattooEvidencePhotoViewProtocol?
    private let wireframe: TattooEvidencePhotoWireframeProtocol
    private let interactor: TattooEvidencePhotoInteractorInputProtocol
    private let design: ProofOfInkPallet.InkSpec
    private let familyId: ProofOfInkPallet.FamilyId
    private let tattooImageViewModelFactory: TattooImageViewModelFactoryProtocol
    private let logger: LoggerProtocol
    private var outlineActionToggleState: Bool = false
    private var isCameraFeedOn: Bool = false

    init(
        interactor: TattooEvidencePhotoInteractorInputProtocol,
        wireframe: TattooEvidencePhotoWireframeProtocol,
        design: ProofOfInkPallet.InkSpec,
        familyId: ProofOfInkPallet.FamilyId,
        tattooImageViewModelFactory: TattooImageViewModelFactoryProtocol,
        logger: LoggerProtocol
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
        self.design = design
        self.familyId = familyId
        self.tattooImageViewModelFactory = tattooImageViewModelFactory
        self.logger = logger
    }
}

private extension TattooEvidencePhotoPresenter {
    func provideViewModel() {
        let viewModel = TattooEvidencePhotoViewModel(
            tipsAction: String(localized: .Tattoo.evidencePhotoActionTips),
            outlineAction: String(localized: .Tattoo.evidencePhotoActionOutlines),
            outlineIcon: outlineActionToggleState ? .tattooOutlineOn : .tattooOutlineOff,
            tattooOverlay: tattooImageViewModelFactory.createViewModelFromInkSpec(design, familyId: familyId),
            isOutlineHidden: !outlineActionToggleState
        )
        view?.didReceive(viewModel: viewModel)
    }
}

extension TattooEvidencePhotoPresenter: TattooEvidencePhotoPresenterProtocol {
    func setup() {
        interactor.setup()
        view?.didReceive(state: .preparing)
        provideViewModel()
    }

    func willAppear() {
        guard isCameraFeedOn else { return }
        view?.didReceive(state: .actionable)
    }

    func capturePhoto() {
        interactor.capturePhoto()
    }

    func toggleTattooOutline() {
        outlineActionToggleState.toggle()
        provideViewModel()
    }

    func showPhotoTips() {
        wireframe.showPhotoTips(from: view)
    }
}

extension TattooEvidencePhotoPresenter: TattooEvidencePhotoInteractorOutputProtocol {
    func didReceive(session: AVCaptureSession) {
        view?.didReceive(session: session)
        view?.didReceive(state: .actionable)
        isCameraFeedOn = true
    }

    func didReceive(error: TattooEvidencePhotoError) {
        logger.error("Did receive error: \(error)")
    }

    func didSaveCapturedPhoto() {
        logger.info("Did capture photo successfully")
        wireframe.presentPhotoPreview(from: view)
    }

    func didReceive(state: TattooEvidencePhotoViewState) {
        view?.didReceive(state: state)
    }
}

extension TattooEvidencePhotoPresenter: @MainActor Localizable {
    func applyLocalization() {
        if let view, view.isSetup {
            provideViewModel()
        }
    }
}
