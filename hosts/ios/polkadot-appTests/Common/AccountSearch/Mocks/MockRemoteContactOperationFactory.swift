@testable import polkadot_app
import Foundation
import Operation_iOS
import SubstrateSdk

final class MockRemoteContactOperationFactory: RemoteContactOperationMaking {
    var searchResult: [Chat.RemoteContact] = []
    var fetchResult: Chat.RemoteContact?

    var searchError: Error?
    var fetchError: Error?

    // Recorded inputs
    var receivedSearchQuery: String?
    var receivedFetchAccountId: AccountId?

    func search(by query: String) -> CompoundOperationWrapper<[Chat.RemoteContact]> {
        receivedSearchQuery = query

        let operation = ClosureOperation<[Chat.RemoteContact]> {
            if let error = self.searchError {
                throw error
            }
            return self.searchResult
        }

        return CompoundOperationWrapper(targetOperation: operation)
    }

    func fetch(by accountId: AccountId) async throws -> Chat.RemoteContact? {
        receivedFetchAccountId = accountId
        if let error = fetchError {
            throw error
        }
        return fetchResult
    }
}
