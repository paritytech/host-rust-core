import Foundation
import Products

@MainActor
protocol ProductGameReminderScheduling: AnyObject {
    func schedule(productId: ProductId, startsAt: Date)

    func cancel(productId: ProductId)
}
