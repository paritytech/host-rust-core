#if TESTNET_FEATURE
    import Foundation
    import Sentry

    protocol IssueMonitoringServicing {
        func setup()
    }

    final class IssueMonitoringService: IssueMonitoringServicing {
        func setup() {
            SentrySDK.start { options in
                options.dsn = GeneratedSecrets.sentryDSN

                // Adds IP for users.
                // For more information, visit: https://docs.sentry.io/platforms/apple/data-management/data-collected/
                options.sendDefaultPii = false

                // Set tracesSampleRate to 1.0 to capture 100% of transactions for performance monitoring.
                // We recommend adjusting this value in production.
                options.tracesSampleRate = 0
            }
        }
    }
#endif
