import Foundation
import UIKit
import SubstrateSdk
import Foundation_iOS
import Individuality

@MainActor
final class TattooListPresenter {
    weak var view: TattooListViewProtocol?
    let wireframe: TattooListWireframeProtocol
    let interactor: TattooListInteractorInputProtocol
    let viewModelFactory: TattooListViewModelFactoryProtocol
    let balanceViewModelFactory: PrimitiveBalanceViewModelFactoryProtocol
    let depositDetailsViewModelFactory: TattooDepositDetailsViewModelMaking
    let candidateAccountId: AccountId
    let logger: LoggerProtocol

    private var families: ProofOfInkPallet.DesignFamiliesResult?
    private var reservedDesigns: ProofOfInkPallet.ReservedDesignsResult?
    private var tattooMetadatas: [ProofOfInkPallet.FamilyId: TattooMetadata] = [:]
    private var personalId: ProofOfInkPallet.PersonalId?
    private var candidateStorage: UncertainStorage<ProofOfInkPallet.Candidate?> = .undefined
    private var requiredPersonBalance: Balance?
    private var currentBalance: Balance?
    private var topUpInProgress: Bool = false

    private weak var discardDimView: DiscardDIMViewProtocol?
    private weak var depositController: UIViewController?

    var isAppliedCandidate: Bool {
        guard case let .defined(candidate) = candidateStorage else {
            return false
        }

        if case .applied = candidate {
            return true
        } else {
            return false
        }
    }

    init(
        interactor: TattooListInteractorInputProtocol,
        wireframe: TattooListWireframeProtocol,
        candidateAccountId: AccountId,
        viewModelFactory: TattooListViewModelFactoryProtocol,
        balanceViewModelFactory: PrimitiveBalanceViewModelFactoryProtocol,
        depositDetailsViewModelFactory: TattooDepositDetailsViewModelMaking,
        logger: LoggerProtocol
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
        self.candidateAccountId = candidateAccountId
        self.viewModelFactory = viewModelFactory
        self.balanceViewModelFactory = balanceViewModelFactory
        self.depositDetailsViewModelFactory = depositDetailsViewModelFactory
        self.logger = logger
    }

    private func getCandidateEntropy() -> Data? {
        switch candidateStorage.value {
        case let .applied(applied):
            applied.entropy
        default:
            nil
        }
    }

    private func getTattooParams() -> TattooGenerationParams? {
        guard let personalId else {
            return nil
        }

        return .init(
            personalId: personalId,
            accountId: candidateAccountId,
            entropy: getCandidateEntropy()
        )
    }

    private func provideViewModel() {
        guard let families, let reservedDesigns, let tattooParams = getTattooParams() else {
            view?.didReceive(viewModels: [])
            return
        }

        var personalFamilies = [(ProofOfInkPallet.FamilyIndex, ProofOfInkPallet.Family)]()
        var otherFamilies = ProofOfInkPallet.DesignFamiliesResult()

        families.filter { tattooMetadatas.keys.contains($0.value.id) }
            .forEach {
                switch $0.value.kind {
                case .proceduralAccount,
                     .proceduralPersonal:
                    personalFamilies.append(($0.key.index, $0.value))
                case .designed,
                     .procedural:
                    otherFamilies[$0.key] = $0.value
                case .unsupported:
                    break
                }
            }

        personalFamilies.sort { $0.0 < $1.0 }

        let personalViewModel = viewModelFactory.createListViewModel(
            from: personalFamilies.map(\.0),
            families: personalFamilies.map(\.1),
            reservedDesigns: reservedDesigns,
            params: tattooParams,
            texts: .init(
                name: String(localized: .Tattoo.listPersonalFamiliesTitle),
                description: String(localized: .Tattoo.listPersonalFamiliesDescription)
            )
        )

        let otherViewModels: [TattooListViewModel] = otherFamilies
            .sorted { $0.key.index < $1.key.index }
            .compactMap { keyValue in
                guard
                    let metadata = tattooMetadatas[keyValue.value.id]?.metadata,
                    let viewModel = viewModelFactory.createListViewModel(
                        from: keyValue.key.index,
                        family: keyValue.value,
                        reserved: reservedDesigns[keyValue.key.index] ?? [],
                        metadata: metadata,
                        params: tattooParams
                    )
                else {
                    return nil
                }
                return viewModel
            }

        var viewModels = [TattooListViewModel]()
        viewModels.reserveCapacity(otherViewModels.count + 1)
        if let personalViewModel {
            viewModels.append(personalViewModel)
        }
        viewModels.append(contentsOf: otherViewModels)

        view?.didReceive(viewModels: viewModels)
    }

    private func provideStateViewModel() {
        guard case .defined = candidateStorage else {
            return
        }

        if isAppliedCandidate {
            view?.didReceive(
                stateViewModel: .applied,
                viewModel: TattooListViewLayout.ViewModel(depositViewType: nil)
            )
            return
        }

        guard let requiredPersonBalance, let currentBalance else {
            return
        }

        if currentBalance >= requiredPersonBalance {
            let confirmViewModel = depositDetailsViewModelFactory.makeApplyWithDeposit(
                deposit: requiredPersonBalance,
                action: { [weak self] in
                    self?.interactor.applyForTattoo()
                }
            )
            view?.didReceive(
                stateViewModel: .applyWithDeposit,
                viewModel: TattooListViewLayout.ViewModel(depositViewType: .confirm(confirmViewModel))
            )
        } else {
            let remaining = requiredPersonBalance.subtractOrZero(currentBalance)
            let depositViewModel = depositDetailsViewModelFactory.makeInsufficientDeposit(
                remaining: remaining,
                inProgress: topUpInProgress,
                action: { [weak self] in
                    self?.addDeposit()
                }
            )
            view?.didReceive(
                stateViewModel: .insufficientDeposit,
                viewModel: TattooListViewLayout.ViewModel(depositViewType: .details(depositViewModel))
            )
        }
    }

    private func shouldDismissDepositView(previousBalance: Balance?, newBalance: Balance) -> Bool {
        guard depositController != nil,
              let previousBalance else {
            return false
        }

        return previousBalance < newBalance
    }
}

extension TattooListPresenter: TattooListPresenterProtocol {
    func setup() {
        provideViewModel()

        interactor.setup()
    }

    func updateOnAppear() {
        interactor.retryReserved()
    }

    func selectCollection(viewModel: TattooListViewModel) {
        guard
            isAppliedCandidate,
            let tattooParams = getTattooParams()
        else {
            return
        }

        let collections: [ProofOfInk.Collection] = viewModel.indices.compactMap {
            guard let family = families?[.init(index: $0)] else {
                return nil
            }
            return ProofOfInk.Collection(familyIndex: $0, family: family)
        }

        guard !collections.isEmpty else {
            return
        }

        wireframe.showTattooCollection(
            from: view,
            sectionMetadata: viewModel.metadata,
            collections: collections,
            tattooParams: tattooParams
        )
    }

    func addDeposit() {
        guard let requiredPersonBalance, let currentBalance else {
            return
        }

        let neededAmount = requiredPersonBalance.subtractOrZero(currentBalance)

        guard neededAmount > 0 else {
            return assertionFailure()
        }

        #if TESTNET_FEATURE
            interactor.addDeposit(amount: neededAmount)
        #else
            depositController = wireframe.showDeposit(from: view, neededAmount: neededAmount)
        #endif
    }

    func presentTattooTermnationConfirmation() {
        let model = DiscardDIMModel { [weak self] in
            self?.interactor.terminateProofOfInk()
        } cancelClosure: { [weak self] in
            self?.wireframe.dismiss(from: self?.view)
        }
        discardDimView = wireframe.showExitConfirmation(from: view, model: model)
    }

    func dismissTattoo() {
        interactor.exitTattoo()
    }
}

extension TattooListPresenter: TattooListInteractorOutputProtocol {
    func didReceiveDesignFamilies(_ families: ProofOfInkPallet.DesignFamiliesResult) {
        logger.debug("Design families: \(families)")

        self.families = families
        interactor.subscribeTattooMetadata(for: families.values.map(\.id))

        provideViewModel()
    }

    func didReceiveReservedDesigns(_ reservedDesigns: ProofOfInkPallet.ReservedDesignsResult) {
        logger.debug("Reserved designs: \(reservedDesigns)")

        self.reservedDesigns = reservedDesigns

        provideViewModel()
    }

    func didReceiveTattooMetadata(_ metadata: TattooMetadata, for family: ProofOfInkPallet.FamilyId) {
        logger.debug("Tattoo metadata: \(metadata)")

        tattooMetadatas[family] = metadata

        provideViewModel()
    }

    func didReceiveNextPersonalId(_ personalId: ProofOfInkPallet.PersonalId) {
        logger.debug("Did receive personalId: \(personalId)")

        self.personalId = personalId

        provideViewModel()
    }

    func didReceiveCandidate(_ candidate: ProofOfInkPallet.Candidate?) {
        logger.debug("Did receive candidate: \(String(describing: candidate))")

        candidateStorage = .defined(candidate)

        provideViewModel()
        provideStateViewModel()
    }

    func didReceiveRequiredPersonBalance(_ balance: Balance) {
        logger.debug("Did receive required person balance: \(balance)")

        requiredPersonBalance = balance

        provideStateViewModel()
    }

    func didReceiveCurrentBalance(_ balance: Balance?) {
        logger.debug("Did receive current balance: \(String(describing: balance))")
        let newBalance = balance ?? .zero
        let shouldHideDepositView = shouldDismissDepositView(previousBalance: currentBalance, newBalance: newBalance)

        currentBalance = newBalance
        provideStateViewModel()

        if shouldHideDepositView {
            wireframe.dismiss(from: view)
        }
    }

    func didReceiveError(_ error: TattooListInteractorError) {
        logger.error("Did receive error: \(error)")

        switch error {
        case .designFamiliesFailed:
            wireframe.presentRequestStatus(on: view) { [weak self] in
                self?.interactor.retryFamilies()
            }
        case .reservedFailed:
            wireframe.presentRequestStatus(on: view) { [weak self] in
                self?.interactor.retryReserved()
            }
        case .tattooMetadataFailed:
            wireframe.presentRequestStatus(on: view) { [weak self] in
                guard let families = self?.families else { return }
                self?.interactor.retryTattooMetadata(for: families.values.map(\.id))
            }
        case .requiredPersonBalance:
            wireframe.presentRequestStatus(on: view) { [weak self] in
                self?.interactor.retryRequiredPersonBalance()
            }
        }
    }

    func didReceiveGeneralError(_ error: Error) {
        _ = wireframe.present(error: error, from: view)
    }

    func didReceiveTermination(inProgress: Bool) {
        discardDimView?.didReceive(activity: inProgress)
    }

    func didReceive(tattooApplyActivity active: Bool) {
        view?.didReceive(tattooApplyActivity: active)
    }

    func didReceiveTopUp(inProgress: Bool) {
        topUpInProgress = inProgress
        provideStateViewModel()
    }
}
