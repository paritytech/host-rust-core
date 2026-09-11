import DesignSystem
import UIKit
import UIKitExt
import SafariServices
import Coinage

@MainActor
final class SettingsPresenter {
    weak var view: SettingsViewProtocol?
    let wireframe: SettingsWireframeProtocol
    let interactor: SettingsInteractorInputProtocol
    let viewModelFactory: SettingsViewModelMaking
    let themeManager: ThemeManagerProtocol

    private var prewarmingToken: SFSafariViewController.PrewarmingToken?
    private var attentionItems: Set<SettingsViewModel.CellType> = []
    private var hasBlockedUsers = false
    private var appVersion: String?
    private var selectedCurrencyCode: String?
    private var selectedPrivacyStrategy: RecyclingStrategyType?

    init(
        interactor: SettingsInteractorInputProtocol,
        wireframe: SettingsWireframeProtocol,
        viewModelFactory: SettingsViewModelMaking,
        themeManager: ThemeManagerProtocol
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
        self.viewModelFactory = viewModelFactory
        self.themeManager = themeManager
    }

    deinit {
        prewarmingToken?.invalidate()
    }
}

private extension SettingsPresenter {
    func visibleCells() -> Set<SettingsViewModel.CellType> {
        let all = Set(SettingsViewModel.Section.allCases.flatMap(\.cells))
        return hasBlockedUsers ? all : all.subtracting([.blockedUsers])
    }

    func fetchURL(for type: SettingsViewModel.CellType) -> URL? {
        switch type {
        case .termsOfUse:
            AppConfig.termsOfUseLink
        case .privacy:
            AppConfig.privacyPolicyLink
        case .backup,
             .theme,
             .currency,
             .linkedDevices,
             .apps,
             .contactUs,
             .blockedUsers:
            nil
        }
    }

    var selectedThemeName: String {
        switch themeManager.mode {
        case let .app(selection): selection.displayName
        }
    }

    func refreshContent() {
        let input = SettingsContentInput(
            visibleCells: visibleCells(),
            attentionItems: attentionItems,
            selectedCurrencyCode: selectedCurrencyCode,
            selectedThemeName: selectedThemeName,
            selectedPrivacyStrategy: selectedPrivacyStrategy,
            appVersion: appVersion,
            onSelect: { [weak self] cellType in
                self?.didTapCell(cellType)
            },
            onSelectPrivacyStrategy: { [weak self] strategy in
                self?.didSelectPrivacyStrategy(strategy)
            }
        )
        view?.applyContent(viewModelFactory.makeContent(input))
    }
}

extension SettingsPresenter: SettingsPresenterProtocol {
    func setup() {
        prewarmingToken = wireframe.prewarmURLs([fetchURL(for: .termsOfUse)])
        interactor.setup()
    }

    func didSelectPrivacyStrategy(_ strategy: RecyclingStrategyType) {
        guard strategy != selectedPrivacyStrategy else { return }
        selectedPrivacyStrategy = strategy
        refreshContent()
        interactor.savePrivacyStrategy(strategy)
    }

    func didTapCell(_ cell: SettingsViewModel.CellType) {
        switch cell {
        case .termsOfUse,
             .privacy:
            guard
                let url = fetchURL(for: cell),
                let view
            else {
                return
            }
            wireframe.showWeb(url: url, from: view, style: WebPresentableStyle(mode: .automatic))
        case .backup:
            wireframe.showBackupFlow(from: view)
        case .theme:
            wireframe.showThemeSelection(from: view) { [weak self] in
                self?.refreshContent()
            }
        case .currency:
            wireframe.showCurrencyPicker(from: view)
        case .linkedDevices:
            wireframe.showLinkedDevices(from: view)
        case .apps:
            wireframe.showApps(from: view)
        case .contactUs:
            interactor.openMailApp()
        case .blockedUsers:
            wireframe.showBlockedUsers(from: view)
        }
    }
}

extension SettingsPresenter: SettingsInteractorOutputProtocol {
    func didReceiveAppVersion(_ appInfo: (version: String, build: String)) {
        appVersion = "v\(appInfo.version) (\(appInfo.build))"
        refreshContent()
    }

    func didReceiveBackupAttention(isRequired: Bool) {
        if isRequired {
            attentionItems.insert(.backup)
        } else {
            attentionItems.remove(.backup)
        }
        refreshContent()
    }

    func didReceiveSelectedCurrency(_ code: String) {
        selectedCurrencyCode = code
        refreshContent()
    }

    func didOpenMailApp() {
        wireframe.openMailComposer(from: view)
    }

    func didFailToOpenMailApp(email: String) {
        wireframe.showContactEmailFallback(email, from: view)
    }

    func didReceiveHasBlockedUsers(_ hasBlockedUsers: Bool) {
        self.hasBlockedUsers = hasBlockedUsers
        refreshContent()
    }

    func didReceivePrivacyStrategy(_ strategy: RecyclingStrategyType) {
        guard strategy != selectedPrivacyStrategy else { return }
        selectedPrivacyStrategy = strategy
        refreshContent()
    }
}
