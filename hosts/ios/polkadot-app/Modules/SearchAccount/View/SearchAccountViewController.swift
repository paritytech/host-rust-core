import UIKit
import Foundation_iOS
import PolkadotUI
import FoundationExt

final class SearchAccountViewController: UIViewController, ViewHolder {
    typealias RootViewType = SearchAccountViewLayout

    typealias Snapshot = NSDiffableDataSourceSnapshot<
        SearchAccountViewModel.Section,
        Cell
    >
    private typealias DataSource = UITableViewDiffableDataSource<
        SearchAccountViewModel.Section,
        Cell
    >

    enum Cell: Hashable {
        case account(SearchAccountViewModel.AccountType)
        case recentContact(RecipientViewModel)

        var accountType: SearchAccountViewModel.AccountType {
            switch self {
            case let .account(accountType): accountType
            case let .recentContact(recentContact): recentContact.accountType
            }
        }
    }

    // MARK: Properties

    let presenter: SearchAccountPresenterProtocol
    private(set) var viewModel = SearchAccountViewModel()
    private lazy var dataSource = configureDataSource()
    private var noResultsQuery: String?

    // MARK: Initial methods

    init(presenter: SearchAccountPresenterProtocol) {
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Life cycle

    override func loadView() {
        view = SearchAccountViewLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureNavigationBar()
        configureLocalization()
        configureActions()
        configureTableView()
        presenter.viewDidLoad()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        setFocusOnSearchBar()
    }

    override func updateContentUnavailableConfiguration(
        using _: UIContentUnavailableConfigurationState
    ) {
        if let noResultsQuery {
            contentUnavailableConfiguration = UIContentUnavailableConfiguration.titleSubtitle(
                with: String(localized: .searchContactNoSuchUsername(username: noResultsQuery)),
                subtitle: ""
            )
        } else {
            contentUnavailableConfiguration = nil
        }
    }

    // MARK: Private methods

    private func configureNavigationBar() {
        navigationItem.rightBarButtonItem = rootView.scanButton
    }

    private func configureLocalization() {
        navigationItem.title = String(localized: .transferSearchMainTitle)

        rootView.addressInputView.titleLabel.text = String(localized: .recipientInputTo)
        rootView.addressInputView.textInputServiceView.applyPasteTitle()

        let placeholder = String(localized: .recipientInputPlaceholder)
        rootView.addressInputView.textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: UIColor.textAndIconsPrimaryLight.withAlphaComponent(0.25),
                .font: UIFont.semibold16
            ]
        )
    }

    private func configureActions() {
        rootView.scanButton.target = self
        rootView.scanButton.action = #selector(didTapScanButton(_:))

        let textInputAction = UIAction { [unowned self] _ in
            presenter.searchAccount(rootView.addressInputView.inputValue)
        }
        let editingEndAction = UIAction { [unowned self] _ in
            presenter.didEndEditingInput(rootView.addressInputView.inputValue)
        }
        rootView.addressInputView.textInputServiceView.addAction(textInputAction, for: .editingChanged)
        rootView.addressInputView.textField.addAction(editingEndAction, for: .editingDidEnd)
    }

    private func configureTableView() {
        rootView.tableView.delegate = self
        rootView.tableView.registerClassForCell(SearchAccountTableViewCell.self)
    }

    private func configureDataSource() -> DataSource {
        let dataSource = DataSource(tableView: rootView.tableView) { tableView, _, item in
            let cell = tableView.dequeueReusableCellWithType(SearchAccountTableViewCell.self)
            cell?.bind(cellType: item)
            cell?.backgroundColor = .clear
            return cell
        }
        dataSource.defaultRowAnimation = .fade

        return dataSource
    }

    private func setFocusOnSearchBar() {
        rootView.addressInputView.textField.becomeFirstResponder()
    }

    private func prepareData(_ dataType: SearchAccountViewModel.DataType) -> Snapshot {
        var snapshot = SearchAccountViewController.Snapshot()
        switch dataType {
        case let .idle(recent, contacts):
            if !recent.isEmpty {
                snapshot.appendSections([.recentContacts])
                snapshot.appendItems(recent.map { .recentContact($0) })
            }
            if !contacts.isEmpty {
                snapshot.appendSections([.default])
                snapshot.appendItems(contacts.map { .account($0) })
            }
        case let .searchResults(accounts):
            snapshot.appendSections([.default])
            snapshot.appendItems(accounts.map { .account($0) })
        }

        return snapshot
    }

    private func applySnapshot(_ snapshot: Snapshot) {
        dataSource.apply(snapshot)
    }

    // MARK: Actions

    @objc
    private func didTapScanButton(_: UIBarButtonItem) {
        presenter.scanQRCode()
    }
}

// MARK: - SearchAccountViewProtocol

extension SearchAccountViewController: SearchAccountViewProtocol {
    func didReceive(_ viewModel: SearchAccountViewModel) {
        rootView.addressInputView.bind(inputViewModel: viewModel.inputViewModel.inputViewModel)
        guard let selectedAccount = viewModel.inputViewModel.selectedAccount else {
            return
        }

        rootView.addressInputView.bind(accountType: selectedAccount)
    }

    func applyData(_ viewModel: SearchAccountViewModel) {
        self.viewModel = viewModel
        let snapshot = prepareData(viewModel.dataType)
        applySnapshot(snapshot)

        let query = rootView.addressInputView.inputValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isEmpty: Bool =
            switch viewModel.dataType {
            case let .idle(recent, contacts): recent.isEmpty && contacts.isEmpty
            case let .searchResults(accounts): accounts.isEmpty
            }

        noResultsQuery = (!query.isEmpty && isEmpty) ? query : nil
        setNeedsUpdateContentUnavailableConfiguration()
    }

    func didStartLoading() {
        noResultsQuery = nil
        setNeedsUpdateContentUnavailableConfiguration()
        let snapshot = dataSource.snapshot()
        let items = snapshot.itemIdentifiers
        if items.isEmpty {
            rootView.loadingView.startAnimating()
            rootView.loadingView.isHidden = false
        }
    }

    func didStopLoading() {
        guard rootView.loadingView.isHidden == false else {
            return
        }

        rootView.loadingView.stopAnimating()
        rootView.loadingView.isHidden = true
    }
}

// MARK: - UITableViewDelegate

extension SearchAccountViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let snapshot = dataSource.snapshot()
        let sections = snapshot.sectionIdentifiers
        let sectionType = sections[safe: section]
        switch sectionType {
        case .recentContacts:
            let frame = CGRect(
                x: .zero,
                y: .zero,
                width: tableView.frame.width,
                height: self.tableView(tableView, heightForHeaderInSection: section)
            )
            return RecentContactsHeaderView(with: sectionType?.title, frame: frame)
        default: return nil
        }
    }

    func tableView(_: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let snapshot = dataSource.snapshot()
        let sectionIdentifier = snapshot.sectionIdentifiers[safe: section]

        switch sectionIdentifier {
        case .recentContacts:
            return 20
        default:
            return .zero
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let snapshot = dataSource.snapshot()
        guard let section = snapshot.sectionIdentifiers[safe: indexPath.section] else {
            return
        }
        let items = snapshot.itemIdentifiers(inSection: section)
        guard let item = items[safe: indexPath.row] else { return }

        rootView.addressInputView.textField.resignFirstResponder()
        presenter.selectAccount(item)
    }
}

private extension TextWithServiceInputView {
    func applyPasteTitle(locale _: Locale = Locale.current) {
        pasteButton.setTitle(
            String(localized: .Common.paste)
        )
    }
}
