import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    let logger: LoggerProtocol = Logger.shared
    #if TESTNET_FEATURE
        let issueMonitoringService: IssueMonitoringServicing = IssueMonitoringService()
    #endif

    var apnsTokenProvider: APNSTokenProviding {
        APNSTokenProviderFacade.sharedManager
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        guard
            !isUnitTesting,
            !isPreviewBuild
        else {
            return true
        }

        #if TESTNET_FEATURE
            issueMonitoringService.setup()
        #endif

        #if FEATURE_DIMS
            DIM1BackgroundTaskRegistrator.shared.registerBackgroundTask()
            PersonRegistrationBackgroundTaskRegistrator.shared.registerBackgroundTask()
            PersonSelfIncludeBackgroundTaskRegistrator.shared.registerBackgroundTask()
        #endif

        UserNotificationService.shared.startGatheringNotifications()

        PushKitService.shared.register(for: [.voIP])
        application.registerForRemoteNotifications()

        return true
    }

    func application(
        _: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options _: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(
        _: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        apnsTokenProvider.setDeviceToken(deviceToken)
    }

    func application(
        _: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        logger.error("DidFailToRegisterForRemoteNotificationsWithError \(error)")
    }
}

var isUnitTesting: Bool {
    #if DEBUG
        ProcessInfo.processInfo.environment.keys.contains("XCTestConfigurationFilePath") ||
            ProcessInfo.processInfo.environment.keys.contains("XCTestBundlePath")
    #else
        false
    #endif
}

var isPreviewBuild: Bool {
    #if DEBUG
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != nil
    #else
        false
    #endif
}
