import Foundation
import BigInt

/// Consolidates all parameters for coin selection.
struct SelectCoinsInput {
    let amount: BigUInt
    let coins: [TrackedCoin]
    let vouchers: [TrackedVoucher]
    let breakdownContext: DenominationBreakdownContext
    let maxVouchersPerGroup: Int
}

/// Protocol defining the coin selection interface.
protocol CoinSelecting {
    /// Selects coins and/or vouchers to fulfill the target amount.
    ///
    /// - Parameter input: All parameters for coin selection including breakdownContext
    /// - Returns: A `CoinSelectionResult` describing the optimal strategy
    /// - Throws: `CoinSelectionError` if selection fails
    func selectCoins(_ input: SelectCoinsInput) async throws -> CoinSelectionResult
}

/// Selects coins and vouchers to fulfill a target amount using optimal strategy.
///
/// Strategies are evaluated in priority order (minimize transactions, then tokens):
/// 1. Exact match with existing coins (0 tx, 0 tokens)
/// 2. Split single coin (1 tx, 0 tokens)
/// 3. Unload vouchers into coins (1 tx, 1+ tokens) - atomic operation
struct CoinSelector {}

// MARK: - CoinSelecting

extension CoinSelector: CoinSelecting {
    func selectCoins(_ input: SelectCoinsInput) async throws -> CoinSelectionResult {
        guard input.amount > 0 else {
            throw CoinSelectionError.zeroAmount
        }

        // Consume the durability overlay here: past this point strategies work on raw assets.
        let availableCoins = input.coins.filter(\.isSelectable).map(\.coin)
        let availableVouchers = input.vouchers.filter(\.isSelectable).map(\.voucher)

        guard !availableCoins.isEmpty || !availableVouchers.isEmpty else {
            throw CoinSelectionError.emptyWallet
        }

        if let exactMatchCoins = SubsetSumSolver.findExactMatch(
            target: input.amount,
            from: availableCoins,
            breakdownContext: input.breakdownContext
        ) {
            return .exactMatch(coins: exactMatchCoins)
        }

        // Strategy 2: Split single coin (1 tx, 0 tokens)
        if let splitResult = trySplitCoin(
            amount: input.amount,
            from: availableCoins,
            breakdownContext: input.breakdownContext
        ) {
            return splitResult
        }

        // Strategy 3: Unload the selectable vouchers into coins. Per-voucher privacy quality is no
        // longer a selection axis — the strategy-driven balance decides usability, and this draws on
        // whatever the durability overlay marks selectable.
        if let unloaded = try tryUnloadIntoCoins(
            amount: input.amount,
            coins: availableCoins,
            vouchers: availableVouchers,
            maxVouchersPerGroup: input.maxVouchersPerGroup,
            breakdownContext: input.breakdownContext
        ) {
            return unloaded
        }

        // Otherwise, insufficient funds
        throw CoinSelectionError.insufficientFunds
    }
}

// MARK: - Private

private extension CoinSelector {
    /// Strategy 2: Find coins to cover amount using minimum coin count, then split overflow
    ///
    /// Selects coins greedily (largest first) to minimize coin count:
    /// - Coins that fit completely under running total → `wholeCoins` (transferred intact)
    /// - Last coin that pushes sum ≥ amount → `overflowCoin` (split into target + change)
    func trySplitCoin(
        amount: BigUInt,
        from coins: [Coin],
        breakdownContext: DenominationBreakdownContext
    ) -> CoinSelectionResult? {
        let sufficientCoins = coins.filter { coin in
            breakdownContext.valueInPlanks(for: coin.exponent) > amount
        }

        let sortedCoins =
            if !sufficientCoins.isEmpty {
                Array(
                    sufficientCoins
                        .sorted { $0.exponent < $1.exponent }
                        .prefix(1)
                )
            } else {
                coins.sorted { $0.exponent > $1.exponent }
            }

        var wholeCoins: [Coin] = []
        var runningSum = BigUInt(0)

        for coin in sortedCoins {
            let coinValue = breakdownContext.valueInPlanks(for: coin.exponent)
            let newSum = runningSum + coinValue

            if newSum < amount {
                // Coin fits completely under target - becomes a whole coin
                wholeCoins.append(coin)
                runningSum = newSum
            } else {
                // This coin pushes us over (or exactly to) the target - it's the overflow coin
                let remainingNeeded = amount - runningSum

                // Target denominations: what recipient needs from the split
                let targetDenominations = breakdownContext.breakdown(amountInPlanks: remainingNeeded)
                // Change: overflow amount from this coin
                let changeDenominations = breakdownContext.breakdown(amountInPlanks: coinValue - remainingNeeded)

                return .split(
                    wholeCoins: wholeCoins,
                    overflowCoin: coin,
                    targetDenominations: targetDenominations,
                    changeDenominations: changeDenominations
                )
            }
        }

        // All coins combined still don't reach amount - can't do split
        return nil
    }

    /// Strategy 3: Unload vouchers into target denominations (atomic operation)
    ///
    /// This unified strategy covers all voucher-based transfers:
    /// - Pure unload (vouchers only, exact or with change)
    /// - Coins + unload (coins provide partial value, vouchers cover the rest)
    ///
    /// Computes per-recycler-group denominations to satisfy the pallet constraint:
    /// each group's total output must equal its total input.
    func tryUnloadIntoCoins(
        amount: BigUInt,
        coins: [Coin],
        vouchers: [Voucher],
        maxVouchersPerGroup: Int,
        breakdownContext: DenominationBreakdownContext
    ) throws -> CoinSelectionResult? {
        guard !vouchers.isEmpty else { return nil }

        // First, try to find coins that contribute to the target (subset sum)
        // If no exact coin match was found in strategy 1, try partial coin contribution
        var usedCoins: [Coin] = []
        var coinContribution = BigUInt(0)

        // Try to find a coin subset that contributes to the target
        // We want the largest coin contribution that's less than amount
        if !coins.isEmpty {
            // Try exact subset first (would have been caught by strategy 1, but for combined scenarios)
            // Instead, find coins that could contribute to a voucher-based solution
            let sortedCoins = coins.sorted { $0.exponent > $1.exponent }
            for coin in sortedCoins {
                let coinValue = breakdownContext.valueInPlanks(for: coin.exponent)
                if coinContribution + coinValue < amount {
                    usedCoins.append(coin)
                    coinContribution += coinValue
                }
            }
        }

        let needed = amount - coinContribution

        let (selectedVouchers, voucherSum) = findMinimalCover(
            vouchers: vouchers,
            amount: needed,
            breakdownContext: breakdownContext
        )

        // Verify we have enough total value
        let totalValue = coinContribution + voucherSum

        guard totalValue >= amount, !selectedVouchers.isEmpty else {
            return nil
        }

        let perGroupAllocations = try computePerGroupAllocations(
            vouchers: selectedVouchers,
            recipientAmount: needed,
            maxVouchersPerGroup: maxVouchersPerGroup,
            breakdownContext: breakdownContext
        )

        return .unloadIntoCoins(
            coins: usedCoins,
            perGroupAllocations: perGroupAllocations
        )
    }

    /// Groups vouchers by recycler and computes per-group denomination allocations.
    ///
    /// Each recycler group's output must equal its input (pallet constraint).
    /// We allocate the recipient amount across groups (largest first), then
    /// each group's remaining budget becomes its change.
    func computePerGroupAllocations(
        vouchers: [Voucher],
        recipientAmount: BigUInt,
        maxVouchersPerGroup: Int,
        breakdownContext: DenominationBreakdownContext
    ) throws -> [RecyclerGroupAllocation] {
        // Group vouchers by recycler (exponent + index)
        let grouped = try Dictionary(grouping: vouchers) { voucher -> RecyclerKey in
            guard let recycler = voucher.recycler else {
                assertionFailure("Not ready vouchers should be filtered-out earlier")
                throw CoinSelectionError.selectedVoucherIsNotReady
            }
            return RecyclerKey(exponent: voucher.exponent, index: recycler.index)
        }

        // Build group info with budget calculations
        struct GroupInfo {
            let key: RecyclerKey
            let vouchers: [Voucher]
            let budget: BigUInt
        }

        let groups: [GroupInfo] = try grouped.map { key, groupVouchers in
            guard maxVouchersPerGroup > groupVouchers.count else {
                throw CoinSelectionError.tooManyVouchersInGroup(
                    count: groupVouchers.count,
                    max: maxVouchersPerGroup
                )
            }

            let budget = groupVouchers.reduce(BigUInt(0)) {
                $0 + breakdownContext.valueInPlanks(for: $1.exponent)
            }
            return GroupInfo(key: key, vouchers: groupVouchers, budget: budget)
        }

        // Sort groups by exponent descending (largest budget groups first)
        // This ensures large recipient amounts are covered by large groups
        let sortedGroups = groups.sorted { $0.key.exponent > $1.key.exponent }

        var remainingRecipient = recipientAmount
        var allocations: [RecyclerGroupAllocation] = []

        for group in sortedGroups {
            // Allocate this group's budget: recipient first, then change
            let recipientFromGroup = min(remainingRecipient, group.budget)
            remainingRecipient -= recipientFromGroup
            let changeFromGroup = group.budget - recipientFromGroup

            // Compute denominations for this group's allocations
            let recipientDenoms = recipientFromGroup > 0
                ? breakdownContext.breakdown(amountInPlanks: recipientFromGroup)
                : []
            let changeDenoms = changeFromGroup > 0
                ? breakdownContext.breakdown(amountInPlanks: changeFromGroup)
                : []

            allocations.append(RecyclerGroupAllocation(
                recyclerKey: group.key,
                vouchers: group.vouchers,
                recipientDenominations: recipientDenoms,
                changeDenominations: changeDenoms
            ))
        }

        return allocations
    }

    func findMinimalCover(
        vouchers: [Voucher],
        amount: BigUInt,
        breakdownContext: DenominationBreakdownContext
    ) -> (vouchers: [Voucher], totalAmount: BigUInt) {
        let singleSmallestCovering = vouchers
            .sorted(by: { $0.exponent < $1.exponent })
            .first { breakdownContext.valueInPlanks(for: $0.exponent) >= amount }

        guard let singleSmallestCovering else {
            return findVoucherCombination(
                from: vouchers,
                for: amount,
                breakdownContext: breakdownContext
            )
        }

        return (
            [singleSmallestCovering],
            breakdownContext.valueInPlanks(for: singleSmallestCovering.exponent)
        )
    }

    func findVoucherCombination(
        from vouchers: [Voucher],
        for amount: BigUInt,
        breakdownContext: DenominationBreakdownContext
    ) -> (vouchers: [Voucher], totalAmount: BigUInt) {
        var selectedVouchers: [Voucher] = []
        var voucherSum = BigUInt(0)

        let descVouchers = vouchers.sorted(by: { $0.exponent > $1.exponent })

        for voucher in descVouchers {
            selectedVouchers.append(voucher)
            voucherSum += breakdownContext.valueInPlanks(for: voucher.exponent)

            guard voucherSum < amount else { break }
        }

        return (selectedVouchers, voucherSum)
    }
}
