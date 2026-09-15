import UIKit
import Combine
import Foundation
import PushKit
import EventCenter
import PolkadotUI

final class MainTabBarInteractor {
    weak var presenter: MainTabBarInteractorOutputProtocol?

    private let serviceCoordinator: ServiceCoordinatorProtocol
    private let chainStatusProvider: ChainStatusProviding

    private let userNotificationService: UserNotificationServicing
    private let mnemonicBackupHelper: MnemonicBackupHelperProtocol
    private let notificationCenter: NotificationCenter
    private let logger: LoggerProtocol
    private let eventCenter: EventCenterProtocol
    private let urlHandlingService: URLHandlingServiceProtocol
    private let deferredLinkHandler: DeferredLinkHandling
    private let extensionWidgetStreamProvider: ChatExtensionWidgetStreaming
    private let browserCoordinator: SPABrowserCoordinating

    private var availabilityObserver: NSObjectProtocol?
    private var extensionWidgetSubscription: Task<Void, Never>?
    private var chainStatusSubscription: Task<Void, Never>?

    init(
        serviceCoordinator: ServiceCoordinatorProtocol,
        chainStatusProvider: ChainStatusProviding,
        userNotificationService: UserNotificationServicing,
        urlHandlingService: URLHandlingServiceProtocol,
        deferredLinkHandler: DeferredLinkHandling,
        mnemonicBackupHelper: MnemonicBackupHelperProtocol,
        browserCoordinator: SPABrowserCoordinating,
        notificationCenter: NotificationCenter = .default,
        logger: LoggerProtocol = Logger.shared,
        eventCenter: EventCenterProtocol = EventCenter.shared,
        extensionWidgetStreamProvider: ChatExtensionWidgetStreaming? = nil
    ) {
        self.serviceCoordinator = serviceCoordinator
        self.chainStatusProvider = chainStatusProvider
        self.userNotificationService = userNotificationService
        self.mnemonicBackupHelper = mnemonicBackupHelper
        self.notificationCenter = notificationCenter
        self.logger = logger
        self.eventCenter = eventCenter
        self.urlHandlingService = urlHandlingService
        self.deferredLinkHandler = deferredLinkHandler
        self.browserCoordinator = browserCoordinator
        self.extensionWidgetStreamProvider = extensionWidgetStreamProvider ?? ChatExtensionWidgetStreamProvider(
            registry: serviceCoordinator.chatExtensionsRegistry,
            logger: logger
        )
    }

    deinit {
        unsubscribeFromExtensionWidgets()
        serviceCoordinator.throttle()
        removeBackupObservers()
        chainStatusSubscription?.cancel()
    }
}

extension MainTabBarInteractor: MainTabBarInteractorInputProtocol {
    func setup() {
        serviceCoordinator.setup()
        requestNotificationsAuthorization()
        subscribeToBackupAvailability()
        subscribeToBackupStatusChanges()
        subscribeToExtensionWidgets()
        evaluateBackupRequirement()
        deferredLinkHandler.register(urlHandlingService)
        subscribeToSPATabs()
        subscribeToChainStatus()
    }
}

private extension MainTabBarInteractor {
    func subscribeToChainStatus() {
        chainStatusSubscription = Task { [weak self, chainStatusProvider, logger] in
            do {
                let statusStream = chainStatusProvider.statusStream()

                for try await rows in statusStream {
                    await self?.handleChainStatusUpdate(rows)
                }
            } catch {
                logger.error("Chain status stream failed: \(error)")
            }
        }
    }

    func requestNotificationsAuthorization() {
        userNotificationService.requestNotificationsAuthorization(completion: nil)
    }

    func subscribeToBackupAvailability() {
        guard availabilityObserver == nil else {
            return
        }
        availabilityObserver = notificationCenter.addObserver(
            forName: mnemonicBackupHelper.didChangeAvailabilityNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.evaluateBackupRequirement()
        }
    }

    func removeBackupObservers() {
        if let availabilityObserver {
            notificationCenter.removeObserver(availabilityObserver)
        }
        availabilityObserver = nil
    }

    func evaluateBackupRequirement() {
        Task { [self] in
            let needsAttention: Bool

            if !mnemonicBackupHelper.isAvailable {
                needsAttention = true
            } else {
                do {
                    needsAttention = try !mnemonicBackupHelper.checkForBackup()
                } catch {
                    logger.warning("Failed to check backup status: \(error.localizedDescription)")
                    needsAttention = true
                }
            }

            await presenter?.didUpdateSettingsAttention(isVisible: needsAttention)
        }
    }

    func subscribeToBackupStatusChanges() {
        eventCenter.add(observer: self, dispatchIn: .main)
    }

    func subscribeToExtensionWidgets() {
        guard extensionWidgetSubscription == nil else {
            return
        }

        extensionWidgetSubscription = Task { [weak self, extensionWidgetStreamProvider] in
            do {
                let widgetConfigurationStream = extensionWidgetStreamProvider.widgetConfigurationStream()

                guard !Task.isCancelled else {
                    return
                }

                extensionWidgetStreamProvider.setup()

                for try await widget in widgetConfigurationStream {
                    await self?.handleExtensionWidgetUpdate(widget)
                }
            } catch {
                self?.logger.error("Extension widget stream failed: \(error)")
            }
        }
    }

    func unsubscribeFromExtensionWidgets() {
        extensionWidgetSubscription?.cancel()
        extensionWidgetSubscription = nil
        extensionWidgetStreamProvider.throttle()
    }

    func subscribeToSPATabs() {
        MainActor.assumeIsolated {
            browserCoordinator.addObserver(self, sendOnSubscription: true)
        }
    }
}

@MainActor
private extension MainTabBarInteractor {
    func handleExtensionWidgetUpdate(_ update: ChatExtensionWidgetUpdate) {
        if let configuration = update.configuration {
            presenter?.didReceiveWidget(
                configuration: configuration,
                for: update.extensionId
            )
        } else {
            presenter?.didRemoveWidget(for: update.extensionId)
        }
    }

    func requestPolkadotSignIn(with url: URL) {
        presenter?.didReceivePolkadotSignInRequest(with: url)
    }

    func handleChainStatusUpdate(_ rows: [ChainConnectionStatusViewModel]) {
        presenter?.didReceiveChainStatus(rows)
    }
}

extension MainTabBarInteractor: AppEventVisiting {
    func processBackupStatusChanged(event _: BackupStatusChanged) {
        evaluateBackupRequirement()
    }
}

extension MainTabBarInteractor: PolkadotSignInServiceOutputProtocol {
    func didReceiveSignInUrl(_ url: URL) {
        Task { [weak self] in
            await self?.requestPolkadotSignIn(with: url)
        }
    }
}

extension MainTabBarInteractor: SPATabsObserver {
    func didReceiveUpdatedTabs(_ tabs: [SPATab]) {
        presenter?.didReceiveSPATabs(tabs)
    }
}
