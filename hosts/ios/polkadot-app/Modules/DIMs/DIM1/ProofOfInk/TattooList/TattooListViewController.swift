import Foundation_iOS
import UIKit
import FoundationExt

final class TattooListViewController: UIViewController, ViewHolder {
//    enum NavigationBarState {
//        case hidden
//        case dismiss
//        case terminate
//    }

    typealias RootViewType = TattooListViewLayout

    let presenter: TattooListPresenterProtocol

    private var viewModels: [TattooListViewModel] = []
    private var stateViewModel: TattooListStateViewModel?
//    private var navigationBarState: NavigationBarState = .hidden

    init(presenter: TattooListPresenterProtocol) {
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let layout = TattooListViewLayout()
//        let inset = collectionViewTopInset(for: navigationBarState)
//        layout.collectionView.contentInset.top = inset

        view = layout
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupCollectionView()
        presenter.setup()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        presenter.updateOnAppear()
    }

    private func setupCollectionView() {
        rootView.collectionView.registerCellClass(TattooCollectionHeaderCell.self)
        rootView.collectionView.registerCellClass(TattooCollectionCell.self)
        rootView.collectionView.registerCellClass(TattooCollectionFamilyCell.self)

        rootView.collectionView.dataSource = self
        rootView.collectionView.delegate = self
    }

    @objc func actionDeposit() {
        presenter.addDeposit()
    }

    @objc func didTapDismissAction() {
        presenter.dismissTattoo()
    }

    @objc func didTapShowMoreAction() {
        presenter.presentTattooTermnationConfirmation()
    }
}

extension TattooListViewController: UICollectionViewDataSource {
    func numberOfSections(in _: UICollectionView) -> Int {
        TattooListSection.numberOfSections(for: viewModels)
    }

    func collectionView(_: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        TattooListSection(section: section, viewModels: viewModels).numberOfItems
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let row = TattooListRow(indexPath: indexPath, viewModels: viewModels)

        switch row {
        case .header:
            let cell = collectionView.dequeueReusableCellWithType(TattooCollectionHeaderCell.self, for: indexPath)!
            cell.bind(title: String(localized: .Tattoo.listTitle))
            return cell
        case let .tattoo(model):
            let cell = collectionView.dequeueReusableCellWithType(TattooCollectionCell.self, for: indexPath)!

            cell.bind(viewModel: model.item.image)

            return cell
        case let .metadata(model):
            let cell = collectionView.dequeueReusableCellWithType(TattooCollectionFamilyCell.self, for: indexPath)!

            cell.bind(
                title: model.item.texts.name,
                isUnlocked: stateViewModel?.isUnlocked ?? false
            )

            return cell
        }
    }
}

extension TattooListViewController: UICollectionViewDelegate {
    func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let row = TattooListRow(indexPath: indexPath, viewModels: viewModels)

        switch row {
        case .header:
            break
        case let .metadata(metadata):
            presenter.selectCollection(viewModel: viewModels[metadata.collectionIndex])
        case let .tattoo(tattoo):
            presenter.selectCollection(viewModel: viewModels[tattoo.collectionIndex])
        }
    }
}

extension TattooListViewController: TattooListViewProtocol {
    func didReceive(viewModels: [TattooListViewModel]) {
        self.viewModels = viewModels
        rootView.collectionView.reloadData()
    }

    func didReceive(
        stateViewModel: TattooListStateViewModel,
        viewModel: TattooListViewLayout.ViewModel
    ) {
        self.stateViewModel = stateViewModel

//        switch stateViewModel {
//        case .applied:
//            updateNavigationBar(with: .terminate)
//
//        case .applyWithDeposit:
//            updateNavigationBar(with: .dismiss)
//
//        case .insufficientDeposit:
//            updateNavigationBar(with: .dismiss)
//        }

        rootView.bind(viewModel: viewModel)
        rootView.collectionView.reloadData()
    }

    func didReceive(tattooApplyActivity active: Bool) {
        rootView.bind(tattooApplyActivity: active)
    }
}

extension TattooListViewController: Localizable {
    func applyLocalization() {
        if isViewLoaded {
            rootView.collectionView.reloadData()
        }
    }
}

// private extension TattooListViewController {
//    func updateNavigationBar(with state: NavigationBarState) {
//        navigationBarState = state
//
//        navigationItem.leftBarButtonItem = nil
//        navigationItem.rightBarButtonItem = nil
//
//        switch navigationBarState {
//        case .hidden:
//            break
//        case .dismiss:
//            navigationItem.leftBarButtonItem = UIBarButtonItem(
//                image: .buttonClose,
//                style: .plain,
//                target: self,
//                action: #selector(didTapDismissAction)
//            )
//        case .terminate:
//            navigationItem.rightBarButtonItem = UIBarButtonItem(
//                image: .showMore,
//                style: .plain,
//                target: self,
//                action: #selector(didTapShowMoreAction)
//            )
//        }
//
//        navigationController?.setNavigationBarHidden(hideBar, animated: false)
//        rootView.collectionView.contentInset.top = collectionViewTopInset(for: state)
//    }
//
//    func collectionViewTopInset(for state: NavigationBarState) -> CGFloat {
//        switch state {
//        case .hidden:
//            44
//        case .dismiss:
//            0
//        case .terminate:
//            0
//        }
//    }
// }

// extension TattooListViewController: HiddableBarWhenPushed {
//    var hideBar: Bool {
//        switch navigationBarState {
//        case .hidden:
//            true
//        case .dismiss:
//            false
//        case .terminate:
//            false
//        }
//    }
// }
