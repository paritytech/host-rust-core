import Foundation
import SubstrateSdk
import SubstrateSdkExt
import Individuality
import Combine

protocol ChatIdentifierServiceProtocol {
    /// Creates a one-time query to **Game.CommunicationIdentifiers** storage
    func fetch(for accountId: AccountId) async throws -> Chat.OnChainEncryptionIdentifier?
}

final class ChatIdentifierService: BaseSubscriptionService {}

extension ChatIdentifierService: ChatIdentifierServiceProtocol {
    func fetch(for accountId: AccountId) async throws -> Chat.OnChainEncryptionIdentifier? {
        let path = GamePallet.Storage.communicationIdentifier(accountId)

        let publisher: AnyPublisher<BytesCodable?, Error> = queryStorage(
            at: path,
            params: [BytesCodable(wrappedValue: accountId)]
        )

        do {
            for try await value in publisher.values {
                guard let container = value?.wrappedValue else {
                    return nil
                }
                return try Chat.OnChainEncryptionIdentifier.fromScaleEncoded(container)
            }
            // Stream finished without value
            return nil
        } catch SubscriptionServiceError.noData {
            return nil
        } catch {
            throw error
        }
    }
}
