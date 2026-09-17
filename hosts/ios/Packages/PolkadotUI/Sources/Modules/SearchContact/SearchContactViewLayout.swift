import DesignSystem
import UIKit
internal import SnapKit
internal import UIKit_iOS

public final class SearchContactViewLayout: DiffableCollectionViewProviderView<String, String> {
    private let searchHeader = SearchContactHeaderView()

    private let separatorSuffix = "_separator"
    private let headerSuffix = "_header"

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

        searchHintLabel.setHidden(true)
        noResultsLabel.setHidden(true)
        loadingView.setHidden(true)

        addSubview(searchHeader)
        addSubview(collectionView)
        addSubview(searchHintLabel)
        addSubview(noResultsLabel)
        addSubview(loadingView)

        let centeringLayoutGuide = UILayoutGuide()
        addLayoutGuide(centeringLayoutGuide)

        centeringLayoutGuide.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview()
            $0.top.equalTo(safeAreaLayoutGuide.snp.top)
            $0.bottom.equalTo(searchHeader.snp.top)
        }

        searchHeader.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview()
            $0.bottom.equalTo(keyboardLayoutGuide.snp.top)
        }

        searchHintLabel.snp.makeConstraints {
            $0.bottom.equalTo(searchHeader.snp.top).offset(-12)
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
            $0.top.equalTo(safeAreaLayoutGuide.snp.top)
            $0.leading.trailing.equalToSuperview()
            $0.bottom.equalTo(searchHeader.snp.top)
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

        CollectionRegistration.registerCell(
            UICollectionViewCell.self,
            for: collectionView,
            reuseId: SearchContactSectionHeaderView.reuseIdentifier
        )
    }
}

public extension SearchContactViewLayout {
    /// Everything the layout shows around the rows: hint, failure text and loader.
    /// Pushed on its own while a search is in flight, so the rows already on screen stay put.
    struct StatusViewModel {
        public let showHint: Bool
        public let searchFailReason: NSAttributedString?
        public let showsLoader: Bool
        public let loaderText: String?

        public init(
            showHint: Bool = false,
            searchFailReason: NSAttributedString? = nil,
            showsLoader: Bool = false,
            loaderText: String? = nil
        ) {
            self.showHint = showHint
            self.searchFailReason = searchFailReason
            self.showsLoader = showsLoader
            self.loaderText = loaderText
        }
    }

    struct ViewModel {
        public struct Section {
            public let id: String
            public let title: String?
            public let rows: [IdentifiableContentConfiguration<String, SearchContactListConfiguration>]

            public init(
                id: String,
                title: String?,
                rows: [IdentifiableContentConfiguration<String, SearchContactListConfiguration>]
            ) {
                self.id = id
                self.title = title
                self.rows = rows
            }
        }

        let sections: [Section]
        let status: StatusViewModel

        public init(sections: [Section], status: StatusViewModel) {
            self.sections = sections
            self.status = status
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

    func bind(status: StatusViewModel) {
        searchHintLabel.setHidden(!status.showHint)
        noResultsLabel.attributedText = status.searchFailReason
        noResultsLabel.setHidden(status.searchFailReason == nil)
        loadingView.bind(text: status.loaderText)
        loadingView.setLoading(status.showsLoader)
    }

    func bind(viewModel: ViewModel) {
        configureCollectionView(viewModel: viewModel)
        bind(status: viewModel.status)
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
        let sectionProviders = viewModel.sections.map { section in
            createSectionProvider(for: section)
        }
        applySnapshot(sections: sectionProviders)
    }

    func createSectionProvider(for section: ViewModel.Section) -> SectionProviderType {
        var items: [ItemProviderType] = []

        if let title = section.title {
            items.append(
                ItemProviderType(
                    id: section.id + headerSuffix,
                    configuration: SearchContactSectionHeaderConfiguration(title: title),
                    reuseIdentifier: SearchContactSectionHeaderView.reuseIdentifier
                )
            )
        }

        section.rows.enumerated().forEach { offset, item in
            items.append(
                ItemProviderType(
                    id: item.id,
                    configuration: item.configuration,
                    reuseIdentifier: SearchContactListView.reuseIdentifier
                )
            )

            if offset < section.rows.count - 1 {
                items.append(
                    ItemProviderType(
                        id: item.id + separatorSuffix,
                        configuration: separatorConfiguration,
                        reuseIdentifier: SeparatorContentView.reuseIdentifier
                    )
                )
            }
        }

        return SectionProviderType(
            id: section.id,
            itemProviders: items
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
    let section = SearchContactViewLayout.ViewModel.Section(
        id: "contacts",
        title: nil,
        rows: contacts.identifiedByUUIDs()
    )
    let viewModel = SearchContactViewLayout.ViewModel(
        sections: [section],
        status: SearchContactViewLayout.StatusViewModel()
    )
    layout.bind(viewModel: viewModel)
    return layout
}

#Preview("No search results") {
    let layout = SearchContactViewLayout()
    let string = NSAttributedString(string: "No results for\n\"notfoundusername\"")
    let viewModel = SearchContactViewLayout.ViewModel(
        sections: [],
        status: SearchContactViewLayout.StatusViewModel(searchFailReason: string)
    )
    layout.bind(viewModel: viewModel)
    return layout
}

#Preview("Empty input") {
    let layout = SearchContactViewLayout()
    let viewModel = SearchContactViewLayout.ViewModel(
        sections: [],
        status: SearchContactViewLayout.StatusViewModel(showHint: true)
    )
    layout.bind(viewModel: viewModel)
    return layout
}

#Preview("Loading") {
    let layout = SearchContactViewLayout()
    let viewModel = SearchContactViewLayout.ViewModel(
        sections: [],
        status: SearchContactViewLayout.StatusViewModel(
            showsLoader: true,
            loaderText: "Search is taking longer than usual"
        )
    )
    layout.bind(viewModel: viewModel)
    return layout
}

#Preview("Multiple sections with headers") {
    let layout = SearchContactViewLayout()
    let recentContacts = [
        SearchContactListConfiguration(
            userName: "Alice.01",
            avatarViewModel: .colored(text: "A", colorSeed: "alice")
        ),
        SearchContactListConfiguration(
            userName: "Bob.02",
            avatarViewModel: .colored(text: "B", colorSeed: "bob")
        )
    ]
    let otherContacts = [
        SearchContactListConfiguration(
            userName: "Charlie.03",
            avatarViewModel: .colored(text: "C", colorSeed: "charlie")
        ),
        SearchContactListConfiguration(
            userName: "Diana.04",
            avatarViewModel: .colored(text: "D", colorSeed: "diana")
        )
    ]

    let sections = [
        SearchContactViewLayout.ViewModel.Section(
            id: "recent",
            title: "Recent",
            rows: recentContacts.identifiedByUUIDs()
        ),
        SearchContactViewLayout.ViewModel.Section(
            id: "other",
            title: "Other",
            rows: otherContacts.identifiedByUUIDs()
        )
    ]
    let viewModel = SearchContactViewLayout.ViewModel(
        sections: sections,
        status: SearchContactViewLayout.StatusViewModel()
    )
    layout.bind(viewModel: viewModel)
    return layout
}
