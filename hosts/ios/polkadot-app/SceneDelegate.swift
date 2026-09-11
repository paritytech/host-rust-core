import ChainRegistry
import DesignSystem
import StructuredConcurrency
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    let linkHandler: DeferredLinkHandling = DeferredLinkHandler.shared

    private var presenter: RootPresenterProtocol?

    #if TESTNET_FEATURE
        private var stallBannerPresenter: StallBannerPresenter?
    #endif

    func scene(
        _ scene: UIScene,
        willConnectTo _: UISceneSession,
        options: UIScene.ConnectionOptions
    ) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        guard
            !isUnitTesting,
            !isPreviewBuild
        else {
            return
        }

        initializeApp(windowScene)
        handleContexts(with: options.urlContexts)
        handleUserActivities(options.userActivities)
    }

    func scene(_: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        handleContexts(with: URLContexts)
    }

    func scene(_: UIScene, continue userActivity: NSUserActivity) {
        handleUserActivities([userActivity])
    }
}

extension SceneDelegate {
    private func initializeApp(_ scene: UIWindowScene) {
        ThemeManager.shared.setup(scene: scene)
        TypographyManager.shared.setup(scene: scene)

        let rootWindow = RootWindow(windowScene: scene)
        window = rootWindow

        attachRootPresenter(to: rootWindow)

        #if TESTNET_FEATURE
            // Package-level instrumentation is inert until this is set.
            // Must be set before any staleness flow can start.
            StalenessReport.isEnabled = true

            let board = StallBoard(sources: [StalenessReport.shared])

            stallBannerPresenter = StallBannerPresenter(
                board: board,
                viewModelFactory: StallBannerViewModelFactory(),
                windowScene: scene
            )
            stallBannerPresenter?.setup()
        #endif

        window?.makeKeyAndVisible()
    }

    private func handleContexts(with contexts: Set<UIOpenURLContext>) {
        guard let context = contexts.first else {
            return
        }
        linkHandler.handle(with: context.url)
    }

    private func handleUserActivities(_ activities: Set<NSUserActivity>) {
        guard
            let url = activities
            .first(where: { $0.activityType == NSUserActivityTypeBrowsingWeb })?
            .webpageURL
        else {
            return
        }
        linkHandler.handle(with: url)
    }

    private func attachRootPresenter(to window: UIWindow) {
        presenter = RootPresenterFactory.createPresenter(with: window)
        presenter?.loadOnLaunch { [weak self] in
            self?.presenter = nil

            UserNotificationService.shared.activatePushNotificationsHandling()
        }
    }
}

#if TESTNET_FEATURE
    extension SceneDelegate {
        func restartScene() {
            guard let window else { return }
            attachRootPresenter(to: window)
        }
    }
#endif
