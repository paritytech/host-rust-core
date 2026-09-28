import Foundation
import os
import Products
import TrUAPIHost

/// Serves one product's slice of the collection to the core.
///
/// Both callbacks run inline on the core's dispatcher thread, so neither may
/// await: the list is answered from a snapshot, and a removal decides against
/// that same snapshot before touching storage.
final class ProductPocketHostBridge: PocketHostBridge, @unchecked Sendable {
    private let productId: String
    private let collection: any PocketCollection
    private let logger: LoggerProtocol
    private let snapshot = OSAllocatedUnfairLock(initialState: [PocketCard]())
    private let republish = OSAllocatedUnfairLock(initialState: (([PocketCard]) -> Void)?.none)

    init(productId: String, collection: any PocketCollection, logger: LoggerProtocol = Logger.shared) {
        self.productId = productId
        self.collection = collection
        self.logger = logger
    }

    /// Starts republishing this product's cards to the core, beginning with the
    /// snapshot as it stands. `publish` is handed the execution, which its
    /// owner closes, so it is dropped on ``stop()``.
    ///
    /// The opening publish is what closes the boot window: the snapshot is
    /// filled before the worker's script comes up, so every change taken into
    /// it until here was seen by nobody.
    func start(publish: @escaping ([PocketCard]) -> Void) {
        republish.withLock { $0 = publish }
        publish(snapshot.withLock { $0 })
    }

    func stop() {
        republish.withLock { $0 = nil }
    }

    /// Re-reads the collection and tells the core only if this product's own
    /// slice changed. A face streaming at frame rate changes the stored
    /// collection continuously without changing any card the core knows about.
    func refresh() async {
        guard let held = try? await collection.cards() else {
            logger.error("[pocket] \(productId)'s slice could not be read; the core keeps the last one")
            return
        }

        let current = held
            .filter { $0.key.productId == productId }
            .map { PocketCard(cardId: $0.key.cardId.value, privileged: $0.privileged) }

        let changed = snapshot.withLock { held -> Bool in
            guard held != current else { return false }
            held = current
            return true
        }
        guard changed else { return }

        republish.withLock { $0 }?(current)
    }

    func listCards() throws -> [PocketCard] {
        snapshot.withLock { $0 }
    }

    func removeCard(cardId: String) throws -> NativePocketRemoval {
        let held = snapshot.withLock { $0 }

        // Both answered from the snapshot, which is what the core was served in
        // the first place. Neither touches storage, so neither pays the
        // blocking read below on the core's own thread.
        if held.contains(where: { $0.cardId == cardId && $0.privileged }) { return .privileged }
        guard held.contains(where: { $0.cardId == cardId }) else { return .absent }

        let key = PocketCardKey(productId: productId, cardId: PocketCardId(value: cardId))
        let outcome = try blockingRemove(key)

        if outcome == .removed {
            snapshot.withLock { $0.removeAll { $0.cardId == cardId } }
        }
        return outcome
    }

    /// The core waits on this answer, so the removal is completed here rather
    /// than handed to a task the caller cannot observe.
    ///
    /// A removal that could not be stored is raised rather than answered as
    /// absent: the core tells the two apart, and a product told its card is
    /// gone while the Pocket still draws it will not ask again.
    private func blockingRemove(_ key: PocketCardKey) throws -> NativePocketRemoval {
        let result = OSAllocatedUnfairLock(initialState: Result<NativePocketRemoval, any Error>.success(.absent))
        let done = DispatchSemaphore(value: 0)

        Task {
            let outcome: Result<NativePocketRemoval, any Error>
            do {
                outcome = try await .success(collection.removeCard(key) == .removed ? .removed : .absent)
            } catch PocketRemoveError.privileged {
                outcome = .success(.privileged)
            } catch {
                outcome = .failure(error)
            }
            result.withLock { $0 = outcome }
            done.signal()
        }

        done.wait()
        return try result.withLock { $0 }.get()
    }
}
