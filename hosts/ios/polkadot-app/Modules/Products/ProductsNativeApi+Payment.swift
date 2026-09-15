import BigInt
import Foundation
import Coinage
import KeyDerivation
import Products
import SubstrateSdk
import AsyncExtensions
import StructuredConcurrency

enum PaymentTopUpError: Error, LocalizedError {
    case coinsNotOnChain
    case noCoinsClaimed
    case partialPayment(amount: Balance)

    var errorDescription: String? {
        switch self {
        case .coinsNotOnChain:
            "Top-up coins did not appear on-chain in time"
        case .noCoinsClaimed:
            "No coins were claimed from the provided secret keys"
        case let .partialPayment(amount):
            "PartialPayment:\(amount)"
        }
    }
}

// MARK: - Payments

extension ProductsNativeApi {
    func subscribePaymentBalance() async throws -> AnyAsyncSequence<PaymentBalance> {
        guard
            try await permissionGuard.consumePermission(
                productId: productId,
                permission: .balanceAccess
            ) else {
            throw ProductNativeApiError.permissionDenied
        }

        let coinageService = try requirePaymentsSupport().coinageService
        let balanceService = try await coinageService.coinageBalanceService()
        return balanceService.balanceStream
            .map { balance in
                PaymentBalance(available: balance.availablePrivate)
            }
            .eraseToAnyAsyncSequence()
    }

    func requestPayment(amountInPlanks: String, destination: AccountId) async throws -> PaymentReceipt {
        guard let amount = BigUInt(amountInPlanks) else {
            throw ProductNativeApiError.invalidParam("amountInPlanks")
        }

        let externalPaymentService = try requirePaymentsSupport().externalPaymentService

        try await checkSufficientBalance(amount: amount)
        try await awaitUserApproval(amount: amount, destination: destination)

        let paymentId = try await externalPaymentService.initiatePayment(
            origin: productId,
            amountInPlanks: amount,
            destination: destination
        )

        return PaymentReceipt(paymentId: paymentId)
    }

    func subscribePaymentStatus(paymentId: String) async throws -> AnyAsyncSequence<HostPaymentStatus> {
        let externalPaymentService = try requirePaymentsSupport().externalPaymentService
        return try externalPaymentService.subscribePaymentStatus(paymentId: paymentId)
            .map { status in
                switch status {
                case .processing: .processing
                case .completed: .completed
                case let .failed(reason): .failed(reason: reason)
                }
            }
            .eraseToAnyAsyncSequence()
    }

    func paymentTopUp(amount: Balance, source: PaymentTopUpSource) async throws {
        let coinageService = try requirePaymentsSupport().coinageService
        let contextSource = try resolveTopUpSource(source: source, callingProductId: productId)
        let context = TopUpRequestContext(
            productId: productId,
            amount: amount,
            source: contextSource
        )

        try await markStallActivity("Topup") {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                context.setContinuation(continuation)

                switch contextSource {
                case let .wallet(wallet):
                    Task { [coinageService] in
                        await self.runWalletTopUp(
                            context: context,
                            wallet: wallet,
                            amount: amount,
                            coinageService: coinageService
                        )
                    }
                case let .coins(secretKeys):
                    Task { [coinageService] in
                        await self.runCoinsTopUp(
                            context: context,
                            secretKeys: secretKeys,
                            amount: amount,
                            coinageService: coinageService
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Payment Request Checks

private extension ProductsNativeApi {
    func requirePaymentsSupport() throws -> PaymentsSupport {
        guard let paymentsSupport else {
            logger.error("Payment feature requested but payments support is unavailable")
            throw ProductNativeApiError.paymentsNotSupported
        }

        return paymentsSupport
    }

    /// Validates spendable balance covers the requested amount.
    ///
    /// If the product has `balanceAccess` permission, returns `insufficientBalance`
    /// (the product already knows balances). Otherwise returns `rejected`
    /// to avoid leaking balance information.
    func checkSufficientBalance(amount: Balance) async throws {
        guard
            try await permissionGuard.consumePermission(
                productId: productId,
                permission: .balanceAccess
            ) else {
            throw PaymentRequestError.rejected
        }

        let coinageService = try requirePaymentsSupport().coinageService
        let balanceService = try await coinageService.coinageBalanceService()

        var spendable = Balance(0)
        for try await value in balanceService.balanceStream.prefix(1) {
            spendable = value.availablePrivate
        }

        if spendable < amount {
            throw PaymentRequestError.insufficientBalance
        }
    }

    /// Shows the payment request approval sheet and suspends until the user decides.
    func awaitUserApproval(amount: Balance, destination: AccountId) async throws {
        let context = PaymentRequestContext(
            productId: productId,
            amountInPlanks: amount,
            destination: destination
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            context.setContinuation(continuation)
            Task { @MainActor [productsRouter] in
                productsRouter.showPaymentRequest(context: context)
            }
        }
    }
}

// MARK: - Top-Up Helpers

private extension ProductsNativeApi {
    func claimWalletTopUp(
        wallet: any WalletManaging,
        amount: Balance,
        coinageService: any CoinageServicing
    ) async throws {
        let loaded = try await coinageService.loadVouchers(
            amount: amount,
            externalAssetHolder: wallet
        )

        if loaded < amount {
            throw PaymentTopUpError.partialPayment(amount: loaded)
        }
    }

    func runWalletTopUp(
        context: TopUpRequestContext,
        wallet: any WalletManaging,
        amount: Balance,
        coinageService: any CoinageServicing
    ) async {
        do {
            try await claimWalletTopUp(
                wallet: wallet,
                amount: amount,
                coinageService: coinageService
            )
            context.deliverClaimed()
        } catch let PaymentTopUpError.partialPayment(loaded) {
            await productsRouter.showTopUpMismatch(
                context: context,
                claimedAmount: loaded,
                requestedAmount: amount
            )
        } catch {
            logger.error("Wallet topup claim failed: \(error)")
            await productsRouter.showTopUpError(
                context: context,
                error: error
            )
        }
    }

    func claimCoinsTopUp(
        secretKeys: [Data],
        amount: Balance,
        coinageService: any CoinageServicing
    ) async throws {
        let memo = TransferMemo(entries: secretKeys, totalValue: amount)
        let topUpCoinsBlockTimeout: UInt32 = 15

        do {
            try await coinageService.ongoingTransferService.awaitSendOnChain(
                memo: memo,
                blockTimeout: topUpCoinsBlockTimeout
            )
        } catch {
            logger.error(
                "Top-up coins not on-chain within \(topUpCoinsBlockTimeout) blocks: \(error)"
            )
            throw PaymentTopUpError.coinsNotOnChain
        }

        let claimed = try await coinageService.transferCoinsFromSecretKeys(
            secretKeys: secretKeys,
            transferCoins: true
        )

        guard claimed > 0 else {
            throw PaymentTopUpError.noCoinsClaimed
        }

        if claimed < amount {
            throw PaymentTopUpError.partialPayment(amount: claimed)
        }
    }

    func runCoinsTopUp(
        context: TopUpRequestContext,
        secretKeys: [Data],
        amount: Balance,
        coinageService: any CoinageServicing
    ) async {
        do {
            try await claimCoinsTopUp(
                secretKeys: secretKeys,
                amount: amount,
                coinageService: coinageService
            )
            context.deliverClaimed()
        } catch let PaymentTopUpError.partialPayment(claimed) {
            await productsRouter.showTopUpMismatch(
                context: context,
                claimedAmount: claimed,
                requestedAmount: amount
            )
        } catch {
            logger.error("Topup claim failed: \(error)")
            await productsRouter.showTopUpError(
                context: context,
                error: error
            )
        }
    }

    func resolveTopUpSource(
        source: PaymentTopUpSource,
        callingProductId: ProductId
    ) throws -> TopUpRequestContext.Source {
        switch source {
        case let .productAccount(derivationIndex):
            let accountId = ProductAccountId(
                productId: callingProductId,
                derivationIndex: derivationIndex
            )
            let wallet = try DynamicDerivedWallet(
                derivationPath: accountId.derivationPath(),
                entropyManager: entropyManager
            )
            return .wallet(wallet)
        case let .privateKey(secretKey):
            return .wallet(DynamicDerivedWallet(secretKeyProvider: { secretKey }))
        case let .coins(secretKeys):
            return .coins(secretKeys: secretKeys)
        }
    }
}
