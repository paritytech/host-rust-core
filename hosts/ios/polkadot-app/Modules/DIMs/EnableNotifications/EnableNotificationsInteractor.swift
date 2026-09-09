import UIKit
import Operation_iOS
import Keystore_iOS
import NotificationCenter

final class EnableNotificationsInteractor {
    weak var presenter: EnableNotificationsInteractorOutputProtocol?

    let notificationCenter: NotificationCenter
    let localNotificationService: UserNotificationServicing
    var foregroundObserver: NSObjectProtocol?
    var accessDenied: Bool?

    init(
        notificationCenter: NotificationCenter,
        localNotificationService: UserNotificationServicing
    ) {
        self.notificationCenter = notificationCenter
        self.localNotificationService = localNotificationService
    }

    deinit {
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
    }
}

extension EnableNotificationsInteractor: EnableNotificationsInteractorInputProtocol {
    func setup() {
        localNotificationService.notificationAccessStatus { [weak self] status in
            MainActor.assumeIsolated {
                self?.accessDenied = status.denied
                self?.presenter?.didReceive(status: status)
            }
        }
    }

    func requestNotificationsAccess() {
        guard let accessDenied else {
            return
        }
        if accessDenied {
            observeNotificationsAccess()
            MainActor.assumeIsolated {
                presenter?.didReceiveGoToSettings()
            }
        } else {
            localNotificationService.requestNotificationsAuthorization { [weak presenter] granted in
                MainActor.assumeIsolated {
                    presenter?.didReceive(accessGranted: granted)
                }
            }
        }
    }

    func confirmDiscardNotifications() {
        guard let accessDenied else {
            return
        }
        if accessDenied {
            MainActor.assumeIsolated {
                presenter?.didReceive(accessGranted: false)
            }
        } else {
            // anyway request access, even if discard confirmed by the user
            requestNotificationsAccess()
        }
    }
}

extension EnableNotificationsInteractor {
    func observeNotificationsAccess() {
        guard foregroundObserver == nil else { return }

        foregroundObserver = notificationCenter.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            checkNotificationStatus()
        }
    }

    func checkNotificationStatus() {
        localNotificationService.notificationAccessStatus { [weak self] status in
            if status.accessGranted {
                MainActor.assumeIsolated {
                    self?.presenter?.didReceive(accessGranted: true)
                }
            }
            // otherwise user should press "don't enable button"
        }
    }
}
