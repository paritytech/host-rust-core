import UIKit
import Foundation_iOS
import EventCenter
import Coinage

final class SettingsInteractor {
    weak var presenter: SettingsInteractorOutputProtocol?

    let logger: LoggerProtocol
    let mnemonicBackupHelper: MnemonicBackupHelperProtocol
    let selectedCurrencyManager: SelectedCurrencyManaging
    let emailComposePresenter: EmailComposePresenting
    private let notificationCenter: NotificationCenter
    private let eventCenter: EventCenterProtocol
    private let chatContactDataProviderFactory: ChatContactDataProviderMaking
    private let recyclingStrategyProvider: any CoinageRecyclingStrategyProviding
    private var availabilityObserver: NSObjectProtocol?
    private var blockedContactsTask: Task<Void, Never>?
    private var privacyStrategyTask: Task<Void, Never>?

    init(
        logger: LoggerProtocol,
        mnemonicBackupHelper: MnemonicBackupHelperProtocol,
        emailComposePresenter: EmailComposePresenting,
        selectedCurrencyManager: SelectedCurrencyManaging = SelectedCurrencyManager.shared,
        notificationCenter: NotificationCenter = .default,
        eventCenter: EventCenterProtocol = EventCenter.shared,
        chatContactDataProviderFactory: ChatContactDataProviderMaking = ChatContactDataProviderFactory(),
        recyclingStrategyProvider: any CoinageRecyclingStrategyProviding = CoinageRecyclingStrategyStore.shared
    ) {
        self.logger = logger
        self.mnemonicBackupHelper = mnemonicBackupHelper
        self.emailComposePresenter = emailComposePresenter
        self.selectedCurrencyManager = selectedCurrencyManager
        self.notificationCenter = notificationCenter
        self.eventCenter = eventCenter
        self.chatContactDataProviderFactory = chatContactDataProviderFactory
        self.recyclingStrategyProvider = recyclingStrategyProvider
    }

    deinit {
        if let availabilityObserver {
            notificationCenter.removeObserver(availabilityObserver)
        }
        blockedContactsTask?.cancel()
        privacyStrategyTask?.cancel()
    }
}

private extension SettingsInteractor {
    func configureAppVersion() {
        let bundle = Bundle.main
        let appVersion = bundle.appVersion ?? ""
        let buildVersion = bundle.appBuild ?? ""

        Task {
            await presenter?.didReceiveAppVersion((version: appVersion, build: buildVersion))
        }
    }

    func provideBackupAttention() {
        let needsAttention: Bool

        if !mnemonicBackupHelper.isAvailable {
            needsAttention = true
        } else {
            do {
                let hasBackup = try mnemonicBackupHelper.checkForBackup()
                needsAttention = !hasBackup
            } catch {
                logger.debug("Failed to check backup status: \(error)")
                needsAttention = true
            }
        }

        Task {
            await presenter?.didReceiveBackupAttention(isRequired: needsAttention)
        }
    }

    func subscribeToAvailabilityChanges() {
        guard availabilityObserver == nil else {
            return
        }

        availabilityObserver = notificationCenter.addObserver(
            forName: mnemonicBackupHelper.didChangeAvailabilityNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.provideBackupAttention()
        }
    }

    func subscribeToBackupStatusChanges() {
        eventCenter.add(observer: self, dispatchIn: .main)
    }

    func provideSelectedCurrency() {
        Task {
            await presenter?.didReceiveSelectedCurrency(selectedCurrencyManager.selectedCurrency.code)
        }
    }

    func subscribeToBlockedContacts() {
        blockedContactsTask = Task { [weak self, chatContactDataProviderFactory, logger] in
            let stream = chatContactDataProviderFactory.subscribeBlockedContacts()

            do {
                for try await contacts in stream {
                    await self?.presenter?.didReceiveHasBlockedUsers(!contacts.isEmpty)
                }
            } catch {
                logger.error("Blocked contacts subscription error: \(error)")
            }
        }
    }

    func subscribeToPrivacyStrategy() {
        privacyStrategyTask = Task { [weak self, recyclingStrategyProvider, logger] in
            do {
                for try await strategy in recyclingStrategyProvider.strategyStream() {
                    await self?.presenter?.didReceivePrivacyStrategy(strategy)
                }
            } catch {
                logger.error("Privacy strategy subscription error: \(error)")
            }
        }
    }
}

// MARK: - SettingsInteractorInputProtocol

extension SettingsInteractor: SettingsInteractorInputProtocol {
    func setup() {
        subscribeToPrivacyStrategy()
        configureAppVersion()
        subscribeToAvailabilityChanges()
        subscribeToBackupStatusChanges()
        provideBackupAttention()
        provideSelectedCurrency()
        subscribeToBlockedContacts()
    }

    func savePrivacyStrategy(_ strategy: RecyclingStrategyType) {
        recyclingStrategyProvider.save(strategy: strategy)
    }

    func openMailApp() {
        let canSendMail = MainActor.assumeIsolated { emailComposePresenter.canSendMail() }
        if canSendMail {
            Task { await presenter?.didOpenMailApp() }
        } else {
            Task { await presenter?.didFailToOpenMailApp(email: AppConfig.contactEmail) }
        }
    }
}

extension SettingsInteractor: AppEventVisiting {
    func processBackupStatusChanged(event _: BackupStatusChanged) {
        provideBackupAttention()
    }

    func processSelectedCurrencyChanged(event _: SelectedCurrencyChanged) {
        provideSelectedCurrency()
    }
}
