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
    private let snapshot = OSAllocatedUnfairLock(initialState: [PocketCard]())
    private let republish = OSAllocatedUnfairLock(initialState: (([PocketCard]) -> Void)?.none)

    init(productId: String, collection: any PocketCollection) {
        self.productId = productId
        self.collection = collection
    }

    /// Starts republishing this product's cards to the core. `publish` is handed
    /// the execution, which its owner closes, so it is dropped on ``stop()``.
    func start(publish: @escaping ([PocketCard]) -> Void) {
        republish.withLock { $0 = publish }
    }

    func stop() {
        republish.withLock { $0 = nil }
    }

    /// Re-reads the collection and tells the core only if this product's own
    /// slice changed. A face streaming at frame rate changes the stored
    /// collection continuously without changing any card the core knows about.
    func refresh() async {
        let current = await collection.cards()
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
        // Answered from the snapshot: a card the host placed is refused without
        // the blocking read below, which runs on the core's own thread.
        if snapshot.withLock({ $0 }).contains(where: { $0.cardId == cardId && $0.privileged }) {
            return .privileged
        }

        let key = PocketCardKey(productId: productId, cardId: PocketCardId(value: cardId))
        let outcome = blockingRemove(key)

        if outcome == .removed {
            snapshot.withLock { $0.removeAll { $0.cardId == cardId } }
        }
        return outcome
    }

    /// The core waits on this answer, so the removal is completed here rather
    /// than handed to a task the caller cannot observe.
    private func blockingRemove(_ key: PocketCardKey) -> NativePocketRemoval {
        let result = OSAllocatedUnfairLock(initialState: NativePocketRemoval.absent)
        let done = DispatchSemaphore(value: 0)

        Task {
            let outcome: NativePocketRemoval
            do {
                outcome = try await collection.removeCard(key) == .removed ? .removed : .absent
            } catch PocketRemoveError.privileged {
                outcome = .privileged
            } catch {
                outcome = .absent
            }
            result.withLock { $0 = outcome }
            done.signal()
        }

        done.wait()
        return result.withLock { $0 }
    }
}
