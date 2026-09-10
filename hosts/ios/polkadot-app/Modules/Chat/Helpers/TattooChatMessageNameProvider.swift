import Foundation
import Operation_iOS
import Individuality
import PolkadotUI

actor TattooChatMessageNameProvider {
    private let familyId: ProofOfInkPallet.FamilyId
    private var cachedName: String?
    private var nameTask: Task<String?, Never>?
    private var pendingCallback: ((String?) -> Void)?

    nonisolated let jsonLocalSubscriptionFactory: JsonDataProviderFactoryProtocol

    init(
        familyId: ProofOfInkPallet.FamilyId,
        jsonLocalSubscriptionFactory: JsonDataProviderFactoryProtocol = JsonDataProviderFactory.shared
    ) {
        self.familyId = familyId
        self.jsonLocalSubscriptionFactory = jsonLocalSubscriptionFactory
    }
}

extension TattooChatMessageNameProvider: TattooNameProviding {
    nonisolated var identifier: String {
        familyId.toHexString()
    }

    nonisolated func provideName(_ completion: @escaping (String?) -> Void) {
        Task { [weak self] in
            await self?.handleProvideName(completion)
        }
    }

    nonisolated func cancel() {
        Task { [weak self] in
            await self?.handleCancel()
        }
    }
}

private extension TattooChatMessageNameProvider {
    func handleProvideName(
        _ completion: @escaping (String?) -> Void,
        targetQueue: DispatchQueue = .main
    ) async {
        if let cachedName {
            targetQueue.async {
                completion(cachedName)
            }
            return
        }

        // provides callback only for the last call
        pendingCallback = completion

        if nameTask != nil {
            return
        }

        nameTask = Task { [weak self] in
            guard let self else { return nil }
            return await resolveName()
        }

        let name = await nameTask?.value
        cachedName = name

        let callback = pendingCallback
        pendingCallback = nil
        nameTask = nil

        targetQueue.async {
            callback?(name)
        }
    }

    func handleCancel() {
        nameTask?.cancel()
        nameTask = nil
        pendingCallback = nil
    }

    func resolveName() async -> String? {
        var iterator = tattooMetadataStream(for: familyId)
            .filter { $0 != nil }
            .makeAsyncIterator()
        let first = await iterator.next() ?? nil
        return first?.metadata.name
    }
}

extension TattooChatMessageNameProvider: TattooMetadataLocalStorageSubscriber, TattooMetadataLocalSubscriptionHandler {}
