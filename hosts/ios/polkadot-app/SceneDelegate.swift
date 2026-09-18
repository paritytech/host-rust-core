import ChainRegistry
import DesignSystem
import StructuredConcurrency
import UIKit

#if targetEnvironment(simulator)
    import KeyDerivation
    import Keystore_iOS
#endif

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

        #if targetEnvironment(simulator)
            if SPAConfiguration.isSimulatorBrowseRequested {
                prepareTrUAPISimulatorE2EUser()
            }
        #endif

        initializeApp(windowScene)
        handleContexts(with: options.urlContexts)
        handleUserActivities(options.userActivities)

        #if targetEnvironment(simulator)
            openTrUAPIE2EChatIfRequested()
        #endif
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

#if targetEnvironment(simulator)
    private extension SceneDelegate {
        /// Puts a fresh simulator into the state `make ios-chat-run` expects:
        /// the rust runtime on, and an identity so onboarding does not block it.
        func prepareTrUAPISimulatorE2EUser() {
            ThemeSelectionStorage().setSelected()
            SettingsManager.shared.set(value: true, for: .truApiRuntimeEnabled)

            if (try? RootEntropyManager.shared.hasRootEntropy()) != true {
                try? RootEntropyManager.shared.createRootEntropy(Data(repeating: 0x42, count: 16))
            }

            let usernameStorage = UsernameStorage()
            if usernameStorage.username == nil {
                usernameStorage.username = Username(value: "truapi-e2e")
            }
        }

        /// Shows the product's chat, so a custom body is decoded and rendered while
        /// the harness watches. The bot creates the room moments after launch, hence
        /// the retries; each one re-selects the chat tab, so they stop at the first
        /// rendered body.
        func openTrUAPIE2EChatIfRequested() {
            let environment = ProcessInfo.processInfo.environment
            guard environment["TRUAPI_IOS_E2E_OPEN_CHAT"] == "1",
                  let extensionId = environment["TRUAPI_IOS_E2E_CHAT_PRODUCT_HOST"],
                  let roomId = environment["TRUAPI_IOS_E2E_CHAT_ROOM_ID"]
            else {
                return
            }

            Task { @MainActor in
                for _ in 0 ..< 15 {
                    guard !TrUAPIE2EMarkers.exists("custom-renderer-update") else { return }

                    try? await Task.sleep(for: .seconds(1))
                    ModuleNavigator().openChat(.chatExtension(extensionId, roomId: roomId))
                }
            }
        }
    }
#endif
