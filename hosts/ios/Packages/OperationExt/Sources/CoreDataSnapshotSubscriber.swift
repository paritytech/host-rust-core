import Foundation
import CoreData
import Operation_iOS
import SDKLogger

public enum CoreDataSnapshotSubscriberError: Error {
    case serviceError(Error)
    case missingContext
    case fetchFailed(Error)
}

public final class CoreDataSnapshotSubscriber<Model: Identifiable, Entity: NSManagedObject>:
    NSObject,
    NSFetchedResultsControllerDelegate {
    private let service: CoreDataServiceProtocol
    private let mapper: AnyCoreDataMapper<Model, Entity>
    private let fetchRequest: NSFetchRequest<Entity>
    private let callbackQueue: DispatchQueue
    private let logger: SDKLoggerProtocol?
    private let transform: ([Model]) -> [Model]
    private let onUpdate: ([Model]) -> Void
    private let onError: ((Error) -> Void)?

    private var fetchController: NSFetchedResultsController<Entity>?

    public init(
        service: CoreDataServiceProtocol,
        mapper: AnyCoreDataMapper<Model, Entity>,
        fetchRequest: NSFetchRequest<Entity>,
        callbackQueue: DispatchQueue,
        logger: SDKLoggerProtocol? = nil,
        transform: @escaping ([Model]) -> [Model] = { $0 },
        onUpdate: @escaping ([Model]) -> Void,
        onError: ((Error) -> Void)? = nil
    ) {
        self.service = service
        self.mapper = mapper
        self.fetchRequest = fetchRequest
        self.callbackQueue = callbackQueue
        self.logger = logger
        self.transform = transform
        self.onUpdate = onUpdate
        self.onError = onError
        super.init()
    }

    public func start() {
        service.performAsync { [weak self] context, error in
            guard let self else {
                return
            }

            if let error {
                logger?.error("fetchController start error: \(error)")
                notifyError(CoreDataSnapshotSubscriberError.serviceError(error))
                return
            }

            guard let context else {
                logger?.error("fetchController start error: context missed")
                notifyError(CoreDataSnapshotSubscriberError.missingContext)
                return
            }

            let fetchController = NSFetchedResultsController(
                fetchRequest: fetchRequest,
                managedObjectContext: context,
                sectionNameKeyPath: nil,
                cacheName: nil
            )
            fetchController.delegate = self

            do {
                try fetchController.performFetch()
                self.fetchController = fetchController
                deliverSnapshot()
            } catch {
                logger?.error("fetchController performFetch error: \(error)")
                notifyError(CoreDataSnapshotSubscriberError.fetchFailed(error))
            }
        }
    }

    // MARK: - NSFetchedResultsControllerDelegate

    public func controllerDidChangeContent(_: NSFetchedResultsController<NSFetchRequestResult>) {
        deliverSnapshot()
    }
}

private extension CoreDataSnapshotSubscriber {
    func deliverSnapshot() {
        guard let objects = fetchController?.fetchedObjects else {
            return
        }

        let models: [Model] = objects.compactMap { entity in
            do {
                return try mapper.transform(entity: entity)
            } catch {
                logger?.error("Map entity failed: \(error)")
                return nil
            }
        }

        let processedModels = transform(models)

        callbackQueue.async { [onUpdate] in
            onUpdate(processedModels)
        }
    }

    func notifyError(_ error: Error) {
        callbackQueue.async { [onError] in
            onError?(error)
        }
    }
}
