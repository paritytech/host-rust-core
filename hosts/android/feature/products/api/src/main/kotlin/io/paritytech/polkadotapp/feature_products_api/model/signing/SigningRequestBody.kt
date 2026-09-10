package io.paritytech.polkadotapp.feature_products_api.model.signing

import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_products_api.domain.accountsProtocol.VrfTranscriptItem
import io.paritytech.polkadotapp.feature_products_api.model.ProductAccountId
import io.paritytech.polkadotapp.feature_products_api.model.signing.createTransaction.TxPayload

sealed interface SigningRequestBody {
    /** Requests that sign with a product account, identified intrinsically by the payload. */
    sealed interface ProductAccountSigning : SigningRequestBody {
        val account: ProductAccountId
    }

    sealed interface ResultHasSignature : ProductAccountSigning

    /** Requests that sign with a plain account id, which must be reverse-resolved before signing. */
    sealed interface LegacyAccountSigning : SigningRequestBody {
        val account: AccountId
    }

    class Transaction(val payload: SignerPayloadJson) : ResultHasSignature {
        override val account: ProductAccountId get() = payload.account
    }

    class Raw(val payload: SigningRawPayload) : ResultHasSignature {
        override val account: ProductAccountId get() = payload.account
    }

    class CreateTransaction(val payload: TxPayload<ProductAccountId>) : ProductAccountSigning {
        override val account: ProductAccountId get() = payload.signer
    }

    /** RFC-0023: an sr25519 VRF over the transcript recipe `transcriptLabel` + ordered `items`. */
    class SignVrf(
        override val account: ProductAccountId,
        val transcriptLabel: ByteArray,
        val items: List<VrfTranscriptItem>,
    ) : ProductAccountSigning

    class RawLegacy(val payload: SigningRawLegacyPayload) : LegacyAccountSigning {
        override val account: AccountId get() = payload.account
    }

    class CreateTransactionLegacy(val payload: TxPayload<AccountId>) : LegacyAccountSigning {
        override val account: AccountId get() = payload.signer
    }
}
