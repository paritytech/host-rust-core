package io.paritytech.polkadotapp.feature_products_impl.domain.signTransaction

import io.paritytech.polkadotapp.common.utils.WithdrawableAnswer
import io.paritytech.polkadotapp.feature_products_api.model.signing.SignedTransaction
import io.paritytech.polkadotapp.feature_products_api.model.signing.SigningAccount
import io.paritytech.polkadotapp.feature_products_api.model.signing.SigningContext
import io.paritytech.polkadotapp.feature_products_api.model.signing.SigningRequestBody
import java.util.concurrent.CancellationException

class ProductSigningContext(
    override val requesterName: String,
    override val requesterIconUrl: String,
    override val signingRequestBody: SigningRequestBody,
    override val signingAccount: SigningAccount,
) : SigningContext {
    private val result = WithdrawableAnswer<Result<SignedTransaction>>()

    override suspend fun approve(sign: suspend () -> Result<SignedTransaction>): Result<Unit> =
        sign().map { signed -> result.deliver(Result.success(signed)) }

    override suspend fun deliverRejection(): Result<Unit> {
        result.deliver(Result.failure(CancellationException("User rejected")))
        return Result.success(Unit)
    }

    override suspend fun awaitWithdrawal() = result.awaitWithdrawal()

    suspend fun awaitResult(open: suspend () -> Unit): Result<SignedTransaction> = result.await(open)
}
