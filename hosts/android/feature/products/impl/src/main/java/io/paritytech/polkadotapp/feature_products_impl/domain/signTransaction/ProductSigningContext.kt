package io.paritytech.polkadotapp.feature_products_impl.domain.signTransaction

import io.paritytech.polkadotapp.feature_products_api.model.signing.SignedTransaction
import io.paritytech.polkadotapp.feature_products_api.model.signing.SigningAccount
import io.paritytech.polkadotapp.feature_products_api.model.signing.SigningContext
import io.paritytech.polkadotapp.feature_products_api.model.signing.SigningRequestBody
import kotlinx.coroutines.CompletableDeferred
import java.util.concurrent.CancellationException

class ProductSigningContext(
    override val requesterName: String,
    override val requesterIconUrl: String,
    override val signingRequestBody: SigningRequestBody,
    override val signingAccount: SigningAccount,
) : SigningContext {
    private val result = CompletableDeferred<Result<SignedTransaction>>()

    override suspend fun deliverSignedResult(signedTransaction: SignedTransaction): Result<Unit> {
        result.complete(Result.success(signedTransaction))
        return Result.success(Unit)
    }

    override suspend fun deliverRejection(): Result<Unit> {
        result.complete(Result.failure(CancellationException("User rejected")))
        return Result.success(Unit)
    }

    suspend fun awaitResult(): Result<SignedTransaction> = result.await()
}
