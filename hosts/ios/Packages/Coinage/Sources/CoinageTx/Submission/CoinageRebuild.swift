import AsyncExtensions
import DurableTransactions
import ExtrinsicService
import Foundation

/// How long a transaction's rebuilds go on: until `deadline` has passed with its inputs gone from the
/// chain, and past a failed attempt only when `retriesFailures`.
struct RebuildTerms: Equatable, Sendable {
    let deadline: Date
    let retriesFailures: Bool
}

/// What one kind of coinage transaction contributes to ``InputGatedSubmissionPolicy``: how it is read
/// back from the ledger, which on-chain assets it waits for, and how it is built.
///
/// When to wait, build, give up or retry is the policy's alone — this only knows the shape of one kind
/// of transaction.
protocol CoinageRebuild: Sendable {
    /// One transaction resolved for building.
    associatedtype Transaction: Sendable

    /// Identifies one of a transaction's inputs, in whatever form its presence is read.
    associatedtype InputKey: Hashable & Sendable

    /// `nil` when `params` cannot be read, which makes the transaction unbuildable.
    func terms(of params: Data) -> RebuildTerms?

    /// Transactions that cannot be resolved are left out, and given up on: nothing the ledger records
    /// will change, so waiting would be waiting for ever.
    func resolve(
        _ transactions: [ScheduledDurableTx],
        assets: [CoinageTxId: CoinageTxEntry]
    ) async -> [CoinageTxId: Transaction]

    func inputs(of transaction: Transaction) -> Set<InputKey>

    /// Which of `inputs` are present, on every look that could be taken. A look that cannot be taken
    /// must not be emitted: a failed read must never erase what the chain last showed.
    func presence(of inputs: Set<InputKey>) async throws -> AnyAsyncSequence<Set<InputKey>>

    /// One extrinsic per transaction, in the order of `transactions`.
    func build(_ transactions: [Transaction]) async throws -> [ExtrinsicBuiltModel]
}
