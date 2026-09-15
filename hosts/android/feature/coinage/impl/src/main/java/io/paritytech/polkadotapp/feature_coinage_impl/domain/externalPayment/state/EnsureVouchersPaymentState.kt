package io.paritytech.polkadotapp.feature_coinage_impl.domain.externalPayment.state

import dagger.assisted.Assisted
import dagger.assisted.AssistedFactory
import dagger.assisted.AssistedInject
import io.paritytech.polkadotapp.chains.network.binding.Balance
import io.paritytech.polkadotapp.common.data.worker.stateMachine.WorkerStateMachineState.TransitionResult
import io.paritytech.polkadotapp.feature_coinage_api.domain.common.CoinageBalanceConversionContext
import io.paritytech.polkadotapp.feature_coinage_api.domain.common.totalBalance
import io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment.ExternalPaymentPlan
import io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment.ExternalPaymentPlanner
import io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment.PaymentContext
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.RecyclerVoucher
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.CoinageBalanceConverterUseCase
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.CoinageRecyclingUseCase
import io.paritytech.polkadotapp.feature_coinage_impl.data.repository.VoucherRepository
import io.paritytech.polkadotapp.feature_coinage_impl.data.repository.subscribeReadyToUseVouchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.withTimeoutOrNull
import timber.log.Timber
import kotlin.time.Duration.Companion.seconds

class EnsureVouchersPaymentState @AssistedInject constructor(
    @Assisted override val context: PaymentContext,
    private val voucherRepository: VoucherRepository,
    private val coinageRecyclingUseCase: CoinageRecyclingUseCase,
    private val coinageBalanceConverterUseCase: CoinageBalanceConverterUseCase,
    private val externalPaymentPlanner: ExternalPaymentPlanner,
    private val offboardFactory: OffboardVouchersPaymentState.Factory,
) : ExternalPaymentState {
    companion object {
        const val INSUFFICIENT_BALANCE = "insufficient balance"

        private val POST_RECYCLING_MATURITY_TIMEOUT = 20.seconds
    }

    override val id: String = "EnsureVouchers"

    @AssistedFactory
    interface Factory {
        fun create(context: PaymentContext): EnsureVouchersPaymentState
    }

    context(noContext: NoContext)
    override suspend fun performTransition(): TransitionResult<ExternalPaymentState> = runTransition {
        val converter = coinageBalanceConverterUseCase.create().getOrThrow()

        with(converter) {
            val plan = externalPaymentPlanner.plan(context.amount).getOrThrow()
            Timber.d("Plan: $plan")

            val offboarding = when (plan) {
                is ExternalPaymentPlan.Ready -> plan.offboarding

                is ExternalPaymentPlan.NeedsDelayedRetry -> error("Needs delayed retry: ${plan.reason}")

                is ExternalPaymentPlan.LoadCoins -> {
                    Timber.d("Starting recycling coins")

                    coinageRecyclingUseCase.recycle(plan.coinsToLoad).getOrThrow()

                    Timber.d("Recycled coins. Awaiting matured vouchers for $POST_RECYCLING_MATURITY_TIMEOUT")

                    val availableVouchers = awaitMaturedVouchersReachedAmountWithTimeout(context.amount)
                        ?: error("EnsureVouchers: recycled ${plan.coinsToLoad.size} coins but matured vouchers still insufficient; retrying")

                    Timber.d("Got matured vouchers")

                    externalPaymentPlanner.pickOffboarding(availableVouchers, context.amount).getOrThrow()
                }

                is ExternalPaymentPlan.NotEnoughAmount -> {
                    Timber.e("Defensive check: not sufficient amount of tokens to transfer ${context.amount}. Got: $plan")

                    return@runTransition FailedPaymentState(context, INSUFFICIENT_BALANCE)
                }
            }

            Timber.d("Offboarding vouchers. ${offboarding.vouchers.size} vouchers for ${offboarding.vouchers.totalBalance()}. Surplus: ${offboarding.surplus}")

            offboardFactory.create(
                context = context,
                selected = offboarding.vouchers.map(RecyclerVoucher::ringVrfKeyIndex),
                surplusPlanks = offboarding.surplus.value,
            )
        }
    }

    context(coinageContext: CoinageBalanceConversionContext)
    private suspend fun awaitMaturedVouchersReachedAmountWithTimeout(amount: Balance): List<RecyclerVoucher>? {
        return withTimeoutOrNull(POST_RECYCLING_MATURITY_TIMEOUT) {
            awaitMaturedVouchersReachedAmount(amount)
        }
    }

    context(coinageContext: CoinageBalanceConversionContext)
    private suspend fun awaitMaturedVouchersReachedAmount(amount: Balance): List<RecyclerVoucher> {
        return voucherRepository.subscribeReadyToUseVouchers().mapNotNull { matured ->
            val maturedSum = matured.totalBalance()
            matured.takeIf { maturedSum >= amount }
        }.first()
    }
}

internal inline fun runTransition(
    block: () -> ExternalPaymentState,
): TransitionResult<ExternalPaymentState> = runCatching(block)
    .fold(
        onSuccess = { TransitionResult.TransitionPerformed(Result.success(it)) },
        onFailure = { TransitionResult.TransitionPerformed(Result.failure(it)) },
    )
