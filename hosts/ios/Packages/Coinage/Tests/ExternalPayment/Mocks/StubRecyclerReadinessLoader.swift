import Foundation
import SubstrateSdk
import Individuality
@testable import Coinage

/// Answers revision 1 for every recycler key; no ring states.
struct StubRecyclerReadinessLoader: RecyclerReadinessLoading {
    func fetchRevisions(for keys: [RecyclerKey], blockHash _: BlockHashData?) async throws -> [RecyclerKey: UInt32] {
        Dictionary(uniqueKeysWithValues: keys.map { ($0, UInt32(1)) })
    }

    func fetchRecyclerStates(for _: [RecyclerKey]) async throws -> [RecyclerKey: MembersPallet.RingStatus] {
        [:]
    }

    func maxConsolidation() async throws -> UInt32 {
        100
    }
}
