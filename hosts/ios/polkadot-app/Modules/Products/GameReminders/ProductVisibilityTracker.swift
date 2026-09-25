import FoundationExt
import Foundation
import Products

/// Which product's SPA is on screen, and whether the app is active.
struct ProductVisibility: Equatable, Sendable {
    /// The product whose SPA is mounted in the tab bar, `nil` when none is or the app is not active.
    let productId: ProductId?
    let isAppActive: Bool
}

/// A source of ``ProductVisibility`` for the game reminder opener and pill.
@MainActor
protocol ProductVisibilityReporting: AnyObject {
    var current: ProductVisibility { get }
    /// The current visibility, then every change.
    func changes() -> AsyncStream<ProductVisibility>
}

/// Combines the SPA the tab bar has mounted with the application state into one visibility value.
@MainActor
final class ProductVisibilityTracker: ProductVisibilityReporting {
    static let shared = ProductVisibilityTracker()

    private var mountedProductId: ProductId?
    private var isAppActive = true
    private var observers: [UUID: AsyncStream<ProductVisibility>.Continuation] = [:]
    private var lifecycleTasks: [Task<Void, Never>] = []

    private(set) var current = ProductVisibility(productId: nil, isAppActive: true)

    func setMountedProduct(_ productId: ProductId?) {
        mountedProductId = productId
        recompute()
    }

    func setAppActive(_ isActive: Bool) {
        isAppActive = isActive
        recompute()
    }

    func changes() -> AsyncStream<ProductVisibility> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<ProductVisibility>.makeStream(bufferingPolicy: .unbounded)
        continuation.yield(current)
        observers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.observers[id] = nil }
        }
        return stream
    }

    /// Follow the app going to the background and coming back. Calling it again is a no-op.
    func startObservingApplicationState(_ factory: ApplicationStateStreamFactory = ApplicationStateStreamFactory()) {
        guard lifecycleTasks.isEmpty else {
            return
        }
        lifecycleTasks = [
            Task { [weak self] in
                for await _ in factory.stream(for: .didEnterBackground) {
                    self?.setAppActive(false)
                }
            },
            Task { [weak self] in
                for await _ in factory.stream(for: .willEnterForeground) {
                    self?.setAppActive(true)
                }
            }
        ]
    }

    private func recompute() {
        let next = ProductVisibility(productId: isAppActive ? mountedProductId : nil, isAppActive: isAppActive)
        guard next != current else {
            return
        }
        current = next
        observers.values.forEach { $0.yield(next) }
    }
}
