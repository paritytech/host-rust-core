package io.paritytech.polkadotapp.feature_web3summit_impl.data.contract

import io.paritytech.polkadotapp.common.domain.model.AccountId

interface Web3SummitContractRepository {
    suspend fun isCheckedIn(productAccountId: AccountId): Result<Boolean>
}
