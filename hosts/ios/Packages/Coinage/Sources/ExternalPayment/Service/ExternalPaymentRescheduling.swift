import Foundation

/// Observes rescheduled payments and transitions them back to `.plan` when ready.
public protocol ExternalPaymentRescheduling {
    func setup()
    func throttle()
}
