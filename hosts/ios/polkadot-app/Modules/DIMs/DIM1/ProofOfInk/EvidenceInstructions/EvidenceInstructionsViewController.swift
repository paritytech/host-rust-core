import SwiftUI
import UIKit
import PolkadotUI

final class EvidenceInstructionsViewController: UIHostingController<InstructionSheetView> {
    let presenter: EvidenceInstructionsPresenterProtocol

    // MARK: Initial methods

    init(presenter: EvidenceInstructionsPresenterProtocol) {
        self.presenter = presenter
        let placeholder = InstructionSheetViewModel(
            title: "",
            items: [],
            glyphImage: Image(systemName: ""),
            primaryButtonTitle: ""
        )
        super.init(rootView: InstructionSheetView(viewModel: placeholder))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Life cycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .bgSurfaceMain
        presenter.setup()
        setupHandlers()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        presenter.willDisappear()
    }

    private func setupHandlers() {
        rootView.onPrimaryAction = { [weak self] in
            self?.presenter.didTapProceed()
        }

        rootView.onCloseAction = { [weak self] in
            self?.presenter.didTapClose()
        }
    }
}

// MARK: - EvidenceInstructionsViewProtocol

extension EvidenceInstructionsViewController: EvidenceInstructionsViewProtocol {
    func didReceive(viewModel: InstructionSheetViewModel) {
        rootView.viewModel = viewModel
    }
}
