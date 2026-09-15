import Foundation

/// Protocol exposing lifecycle methods for DetermineStateSyncService.
/// Follows the codebase naming convention: [Name]Servicing for service protocols.
protocol DetermineStateSyncServicing: AnyObject {
    func setup()
    func throttle()
}

// MARK: - Conformance

// DetermineStateSyncService already provides setup() and throttle() via BaseSyncService inheritance.
// This extension declares conformance to the protocol.
extension DetermineStateSyncService: DetermineStateSyncServicing {}
