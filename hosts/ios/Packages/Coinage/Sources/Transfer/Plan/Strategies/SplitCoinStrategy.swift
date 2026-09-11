import Foundation
import ExtrinsicService
import StructuredConcurrency
import SubstrateSdk
import SubstrateSdkExt
import SDKLogger

/// Strategy 2: split one coin into recipient and change denominations.
///
/// Only `overflowCoin` is consumed on chain, so it is the entry's single input — which is what
/// Appendix B says a split takes. `wholeCoins` are passed to the recipient untouched and are
/// recorded as handoffs rather than as inputs.
///
/// Both the recipient coins and the change coins are declared as outputs. Recording the
/// recipient side matters: an entry that declares only its change has no evidence left once
/// the peer claims, and cannot be told apart from one that never executed.
struct SplitCoinStrategy {
    private let wholeCoins: [Coin]
    private let overflowCoin: Coin
    private let targetDenominations: [Denomination]
    private let changeDenominations: [Denomination]
    private let minter: any CoinMinting
    private let coinKeyFactory: any CoinKeyDeriving
    private let txService: any CoinageTxServicing
    private let originFactory: OriginCreating
    private let logger: SDKLoggerProtocol?

    init(
        wholeCoins: [Coin],
        overflowCoin: Coin,
        targetDenominations: [Denomination],
        changeDenominations: [Denomination],
        minter: any CoinMinting,
        coinKeyFactory: any CoinKeyDeriving,
        txService: any CoinageTxServicing,
        originFactory: OriginCreating,
        logger: SDKLoggerProtocol?
    ) {
        self.wholeCoins = wholeCoins
        self.overflowCoin = overflowCoin
        self.targetDenominations = targetDenominations
        self.changeDenominations = changeDenominations
        self.minter = minter
        self.coinKeyFactory = coinKeyFactory
        self.txService = txService
        self.originFactory = originFactory
        self.logger = logger
    }
}

// MARK: - TransferStrategy

extension SplitCoinStrategy: TransferStrategy {
    func prepare(groupId: CoinageTxGroupId?) async throws -> PreparedStrategy {
        let recipientCoins = try await minter.mintCoins(targetDenominations.map(\.exponent))
        // Change coins stay ours — minted as outputs but not handed off.
        let changeCoins = try await minter.mintCoins(changeDenominations.map(\.exponent))

        var transaction = CoinageTransaction()
        transaction.mint(coins: recipientCoins + changeCoins)
        transaction.consume(coins: [overflowCoin])
        // Recipient coins are handed off before submit: a key that reaches the recipient without a
        // mark could be selected again. Change coins stay ours and are not handed off.
        transaction.handOff(coins: wholeCoins + recipientCoins)
        let assets = transaction.build()

        let splitDestinations = try buildSplitDestinations(from: assets.outputCoins)

        let call = CoinagePallet.Calls.Split(
            splitInto: splitDestinations.sorted { $0.exponent < $1.exponent }
        )
        let builder: ExtrinsicBuilderClosure = {
            try $0.adding(call: call.callAsFunction())
        }
        let origin = try makeOrigin()

        // One fire-and-forget submit: registers (claiming the input) and broadcasts, returning once
        // the entry is committed. The projection writes below follow, explained by that entry.
        logger?.debug("Submitting split extrinsic for \(assets.outputCoins.count) coins")
        try await txService.submitTransaction(
            request: CoinageTxRequest(
                inputs: assets.inputs,
                outputs: assets.outputs,
                builder: builder,
                origin: origin
            ),
            groupId: groupId
        )

        let handoffCommit = try await txService
            .preCommitHandoff(assets.handedOff.map { .coin($0.derivationIndex, $0.publicKey) })

        var memoEntries = wholeCoins.map {
            PlannedMemoEntry(
                coinDerivationIndex: $0.derivationIndex,
                valueExponent: $0.exponent
            )
        }
        memoEntries += recipientCoins.map {
            PlannedMemoEntry(coinDerivationIndex: $0.derivationIndex, valueExponent: $0.exponent)
        }

        return PreparedStrategy(memoEntries: memoEntries, handoffCommit: handoffCommit)
    }
}

// MARK: - Private

private extension SplitCoinStrategy {
    func buildSplitDestinations(
        from coins: [Coin]
    ) throws -> [CoinagePallet.Calls.Split.SplitDestination] {
        var grouped: [Int16: [Data]] = [:]
        for coin in coins {
            grouped[coin.exponent, default: []].append(coin.publicKey)
        }

        return grouped.map { exponent, accounts in
            CoinagePallet.Calls.Split.SplitDestination(
                exponent: exponent,
                accounts: accounts
            )
        }
    }

    func makeOrigin() throws -> ExtrinsicOriginDefining {
        let coinAccount = try CoinDerivedWallet(
            privateKey: coinKeyFactory.derivePrivateKey(for: overflowCoin),
            publicKey: overflowCoin.publicKey
        )

        return try originFactory.createAsCoinOrigin(for: coinAccount)
    }
}
