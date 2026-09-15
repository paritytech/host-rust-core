import Foundation

protocol SynchronizedTimeServicing {
    var currentTime: Date { get }
}

final class SynchronizedTimeService {}

extension SynchronizedTimeService: SynchronizedTimeServicing {
    var currentTime: Date {
        Date()
    }
}
