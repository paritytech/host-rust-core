import UIKit
import FoundationExt

final class TattooFamilyDetailsViewController: UIViewController, ViewHolder {
    typealias RootViewType = TattooFamilyDetailsViewLayout

    private let presenter: TattooFamilyDetailsPresenterProtocol
    private var viewModel: TattooFamilyDetailsViewModel = .init(items: [])

    init(presenter: TattooFamilyDetailsPresenterProtocol) {
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = TattooFamilyDetailsViewLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpSubviews()
        presenter.setup()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        presenter.updateOnAppear()
    }
}

extension TattooFamilyDetailsViewController: UICollectionViewDataSource {
    func numberOfSections(in _: UICollectionView) -> Int {
        viewModel.items.count
    }

    func collectionView(_: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        viewModel.items[section].count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        switch viewModel.items[indexPath.section][indexPath.row].item {
        case let .header(model):
            let cell = collectionView.dequeueReusableCellWithType(
                TattooFamilyDetailsCollectionHeaderCell.self,
                for: indexPath
            )!
            cell.bind(viewModel: model)
            return cell
        case let .tattoo(model):
            let cell = collectionView.dequeueReusableCellWithType(TattooCollectionCell.self, for: indexPath)!
            cell.bind(viewModel: model.image)
            return cell
        }
    }
}

extension TattooFamilyDetailsViewController: UICollectionViewDelegate {
    func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let action = viewModel.items[indexPath.section][indexPath.row].action else { return }
        presenter.perform(action)
    }
}

private extension TattooFamilyDetailsViewController {
    func setUpSubviews() {
        rootView.collectionView.registerCellClass(TattooFamilyDetailsCollectionHeaderCell.self)
        rootView.collectionView.registerCellClass(TattooCollectionCell.self)
        rootView.collectionView.dataSource = self
        rootView.collectionView.delegate = self
    }
}

extension TattooFamilyDetailsViewController: TattooFamilyDetailsViewProtocol {
    func didReceive(_ viewModel: TattooFamilyDetailsViewModel) {
        self.viewModel = viewModel
        rootView.collectionView.reloadData()
    }
}
