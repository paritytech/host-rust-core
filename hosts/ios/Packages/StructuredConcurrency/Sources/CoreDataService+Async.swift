import CoreData
import Foundation
import Operation_iOS

public extension CoreDataServiceProtocol {
    /// Acquires a managed object context from the service and executes `block`
    /// on the context's queue, bridging the callback-based API to async/await.
    /// `block` is dispatched via `context.perform`, so it is thread-safe and
    /// does not block the caller of `performAsync` waiting for the queue.
    func perform<T>(
        _ block: @escaping (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            performAsync { context, error in
                guard let context else {
                    continuation.resume(throwing: error ?? CoreDataRepositoryError.undefined)
                    return
                }
                context.perform {
                    do {
                        let result = try block(context)
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}
