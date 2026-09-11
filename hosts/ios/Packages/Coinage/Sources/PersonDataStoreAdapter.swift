import Foundation
import CommonService
import Individuality

public struct PersonData: PersonDataProtocol {
    public let personRecord: PeoplePallet.PersonRecord?
    public let ringPosition: MembersPallet.RingPosition?

    public init(personRecord: PeoplePallet.PersonRecord?, ringPosition: MembersPallet.RingPosition?) {
        self.personRecord = personRecord
        self.ringPosition = ringPosition
    }
}

public protocol PersonObservableStateStoreProtocol {
    associatedtype Output: PersonDataProtocol

    func add(
        observer: AnyObject,
        sendStateOnSubscription: Bool,
        queue: DispatchQueue?,
        closure: @escaping Observable<Output?>.StateChangeClosure
    )
    func remove(observer: AnyObject)
    func reset()
}

public final class PersonObservableDataStoreAdapter<T: PersonDataProtocol> {
    public typealias Output = PersonData

    private let observableStore: BaseObservableStateStore<T>

    public init(store: BaseObservableStateStore<T>) {
        observableStore = store
    }
}

extension PersonObservableDataStoreAdapter: PersonObservableStateStoreProtocol {
    public func add(
        observer: AnyObject,
        sendStateOnSubscription: Bool,
        queue: DispatchQueue?,
        closure: @escaping CommonService.Observable<Output?>.StateChangeClosure
    ) {
        observableStore.add(
            observer: observer,
            sendStateOnSubscription: sendStateOnSubscription,
            queue: queue,
            closure: { oldState, newState in
                closure(
                    PersonData(
                        personRecord: oldState?.personRecord,
                        ringPosition: oldState?.ringPosition
                    ),
                    PersonData(
                        personRecord: newState?.personRecord,
                        ringPosition: newState?.ringPosition
                    )
                )
            }
        )
    }

    public func remove(observer: AnyObject) {
        observableStore.remove(observer: observer)
    }

    public func reset() {
        observableStore.reset()
    }
}
