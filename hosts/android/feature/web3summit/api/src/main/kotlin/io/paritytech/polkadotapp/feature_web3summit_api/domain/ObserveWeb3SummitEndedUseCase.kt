package io.paritytech.polkadotapp.feature_web3summit_api.domain

import kotlinx.coroutines.flow.Flow

interface ObserveWeb3SummitEndedUseCase {
    operator fun invoke(): Flow<Boolean>
}
