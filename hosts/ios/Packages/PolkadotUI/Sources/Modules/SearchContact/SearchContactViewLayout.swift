import DesignSystem
import UIKit
internal import SnapKit
internal import UIKit_iOS

public final class SearchContactViewLayout: DiffableCollectionViewProviderView<String, String> {
    private let searchHeader = SearchContactHeaderView()

    private let separatorSuffix = "_separator"

    private let searchHintLabel: Label = create {
        $0.text = String(localized: .searchContactHint)
        $0.typography = .bodyMedium
        $0.textColor = UIColor.fgPrimary
        $0.numberOfLines = 0
        $0.textAlignment = .center
    }

    private let noResultsLabel: Label = create {
        $0.numberOfLines = 0
        $0.textAlignment = .center
    }

    private let loadingView = SearchContactLoadingView()

    private lazy var separatorConfiguration = createSeparatorConfiguration()

    public var selectionHandler: ((ItemIdentifierType) -> Void)?

    override public func setupViews() {
        backgroundColor = .bgSurfaceMain
        collectionView.backgroundColor = .clear
        collectionView.keyboardDismissMode = .onDrag
        collectionView.delegate = self

        // hidden by default
        searchHintLabel.setHidden(true)
        noResultsLabel.setHidden(true)
        loadingView.setHidden(true)

        addSubview(searchHeader)
        addSubview(collectionView)
        addSubview(searchHintLabel)
        addSubview(noResultsLabel)
        addSubview(loadingView)

        // keyboard to search field
        let centeringLayoutGuide = UILayoutGuide()
        addLayoutGuide(centeringLayoutGuide)

        centeringLayoutGuide.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview()
            $0.top.equalTo(searchHeader.snp.bottom)
            $0.bottom.equalTo(keyboardLayoutGuide.snp.top)
        }

        searchHeader.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview()
            $0.top.equalTo(safeAreaLayoutGuide.snp.top).offset(0)
        }

        searchHintLabel.snp.makeConstraints {
            $0.top.equalTo(searchHeader.snp.bottom).offset(12)
            $0.leading.equalToSuperview().offset(24)
            $0.trailing.equalToSuperview().inset(24)
        }

        noResultsLabel.snp.makeConstraints {
            $0.centerX.equalTo(centeringLayoutGuide.snp.centerX)
            $0.centerY.equalTo(centeringLayoutGuide.snp.centerY)
            $0.width.lessThanOrEqualTo(centeringLayoutGuide.snp.width)
            $0.height.lessThanOrEqualTo(centeringLayoutGuide.snp.height)
        }

        loadingView.snp.makeConstraints {
            $0.edges.equalTo(centeringLayoutGuide)
        }

        collectionView.snp.makeConstraints {
            $0.top.equalTo(searchHeader.snp.bottom)
            $0.leading.trailing.bottom.equalToSuperview()
        }
    }

    override public func registerCells() {
        super.registerCells()

        CollectionRegistration.registerCell(
            UICollectionViewCell.self,
            for: collectionView,
            reuseId: SearchContactListView.reuseIdentifier
        )

        CollectionRegistration.registerCell(
            UICollectionViewCell.self,
            for: collectionView,
            reuseId: SeparatorContentView.reuseIdentifier
        )
    }
}

public extension SearchContactViewLayout {
    struct ViewModel {
        let contactsById: [IdentifiableContentConfiguration<ItemIdentifierType, SearchContactListConfiguration>]
        let showHint: Bool
        let searchFailReason: NSAttributedString?
        let showsLoader: Bool
        let loaderText: String?

        public init(
            contactsById: [IdentifiableContentConfiguration<String, SearchContactListConfiguration>],
            showHint: Bool,
            searchFailReason: NSAttributedString?,
            showsLoader: Bool,
            loaderText: String?
        ) {
            self.contactsById = contactsById
            self.showHint = showHint
            self.searchFailReason = searchFailReason
            self.showsLoader = showsLoader
            self.loaderText = loaderText
        }
    }

    var searchHandler: ((String?) -> Void)? {
        get { searchHeader.searchHandler }
        set { searchHeader.searchHandler = newValue }
    }

    var cancelHandler: (() -> Void)? {
        get { searchHeader.cancelHandler }
        set { searchHeader.cancelHandler = newValue }
    }

    var scanHandler: (() -> Void)? {
        get { searchHeader.scanHandler }
        set { searchHeader.scanHandler = newValue }
    }

    func bind(viewModel: ViewModel) {
        configureCollectionView(viewModel: viewModel)
        searchHintLabel.setHidden(!viewModel.showHint)
        noResultsLabel.attributedText = viewModel.searchFailReason
        noResultsLabel.setHidden(viewModel.searchFailReason == nil)
        loadingView.bind(text: viewModel.loaderText)
        loadingView.setLoading(viewModel.showsLoader)
    }

    func focusSearchInput() {
        searchHeader.searchField.becomeFirstResponder()
    }
}

private extension SearchContactViewLayout {
    func createSeparatorConfiguration() -> SeparatorContentConfiguration {
        .init(
            color: UIColor.strokePrimary,
            height: 1,
            insets: NSDirectionalEdgeInsets(
                top: 0,
                leading: 64,
                bottom: 0,
                trailing: 16
            )
        )
    }

    func configureCollectionView(viewModel: ViewModel) {
        let itemProviders = viewModel.contactsById.enumerated().map { offset, item in
            var items: [ItemProviderType] = [
                ItemProviderType(
                    id: item.id,
                    configuration: item.configuration,
                    reuseIdentifier: SearchContactListView.reuseIdentifier
                )
            ]
            if offset < viewModel.contactsById.count - 1 {
                let separator = ItemProviderType(
                    id: item.id + separatorSuffix,
                    configuration: separatorConfiguration,
                    reuseIdentifier: SeparatorContentView.reuseIdentifier
                )
                items.append(separator)
            }
            return items
        }.flatMap { $0 }

        let sectionProvider = SectionProviderType(
            id: "ContactsSection",
            itemProviders: itemProviders
        ) { _, _ in
            let group = NSCollectionLayoutGroup.list(
                heightDimension: .estimated(60),
                widthDimension: .fractionalWidth(1.0)
            )

            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 8
            section.contentInsets = .init(top: 16, leading: 16, bottom: 0, trailing: 16)
            return section
        }
        applySnapshot(sections: [
            sectionProvider
        ])
    }
}

private final class SearchContactLoadingView: UIView {
    private enum Constants {
        static let loadingViewSize = CGFloat(64)
    }

    private let loadingView: LoadingView = create {
        $0.contentBackgroundColor = .clear
        $0.contentSize = .init(width: Constants.loadingViewSize, height: Constants.loadingViewSize)
        $0.indicatorImage = UIImage(resource: .searchingUsername)
        $0.tintColor = .fgPrimary
    }

    private let textLabel: Label = create {
        $0.numberOfLines = 0
        $0.textAlignment = .center
        $0.typography = .bodyLargeEmphasized
        $0.textColor = .fgSecondary
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func bind(text: String?) {
        textLabel.text = text
        textLabel.setHidden(text == nil)
    }

    func setLoading(_ loading: Bool) {
        setHidden(!loading)

        if loading {
            loadingView.startAnimating()
        } else {
            loadingView.stopAnimating()
        }
    }

    private func setupLayout() {
        addSubview(loadingView)
        addSubview(textLabel)

        loadingView.snp.makeConstraints {
            $0.center.equalToSuperview()
            $0.size.equalTo(Constants.loadingViewSize)
        }

        textLabel.snp.makeConstraints {
            $0.top.equalTo(loadingView.snp.bottom).offset(8)
            $0.leading.trailing.equalToSuperview().inset(24)
        }
    }
}

extension SearchContactViewLayout: UICollectionViewDelegate {
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard collectionView.cellForItem(at: indexPath)?.contentView is SearchContactListView,
              let identifier = dataSource.itemIdentifier(for: indexPath) else {
            return
        }
        selectionHandler?(identifier)
    }
}

#Preview("2 contacts found") {
    let layout = SearchContactViewLayout()
    let contacts = [
        SearchContactListConfiguration(
            userName: "Jake.23",
            avatarViewModel: .colored(text: "J", colorSeed: "jake")
        ),
        SearchContactListConfiguration(
            userName: "Max.12",
            avatarViewModel: .colored(text: "M", colorSeed: "max")
        )
    ]
    let viewModel = SearchContactViewLayout.ViewModel(
        contactsById: contacts.identifiedByUUIDs(),
        showHint: false,
        searchFailReason: nil,
        showsLoader: false,
        loaderText: nil
    )
    layout.bind(viewModel: viewModel)
    return layout
}

#Preview("No search results") {
    let layout = SearchContactViewLayout()
    let string = NSAttributedString(string: "No results for\n\"notfoundusername\"")
    let viewModel = SearchContactViewLayout.ViewModel(
        contactsById: [],
        showHint: false,
        searchFailReason: string,
        showsLoader: false,
        loaderText: nil
    )
    layout.bind(viewModel: viewModel)
    return layout
}

#Preview("Empty input") {
    let layout = SearchContactViewLayout()
    let viewModel = SearchContactViewLayout.ViewModel(
        contactsById: [],
        showHint: true,
        searchFailReason: nil,
        showsLoader: false,
        loaderText: nil
    )
    layout.bind(viewModel: viewModel)
    return layout
}

#Preview("Loading") {
    let layout = SearchContactViewLayout()
    let viewModel = SearchContactViewLayout.ViewModel(
        contactsById: [],
        showHint: false,
        searchFailReason: nil,
        showsLoader: true,
        loaderText: "Search is taking longer than usual"
    )
    layout.bind(viewModel: viewModel)
    return layout
}
