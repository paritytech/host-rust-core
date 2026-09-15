package io.paritytech.polkadotapp.feature_products_api.model.signing

interface SigningContext {
    val requesterName: String
    val requesterIconUrl: String
    val signingRequestBody: SigningRequestBody

    /** The account this request signs with, resolved before the signing screen is shown. */
    val signingAccount: SigningAccount

    suspend fun deliverSignedResult(signedTransaction: SignedTransaction): Result<Unit>

    suspend fun deliverRejection(): Result<Unit>
}
