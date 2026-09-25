import Foundation
import PolkadotUI

@testable import polkadot_app

@MainActor
final class FakeAppWidgets: AppWidgetManaging {
    private(set) var attached: [String: any HashableContentConfiguration] = [:]
    private(set) var attachCount = 0

    func attachWidget(_ configuration: any HashableContentConfiguration, for id: AppWidgetID) {
        attached[id.rawValue] = configuration
        attachCount += 1
    }

    func detachWidget(for id: AppWidgetID) {
        attached[id.rawValue] = nil
    }
}
