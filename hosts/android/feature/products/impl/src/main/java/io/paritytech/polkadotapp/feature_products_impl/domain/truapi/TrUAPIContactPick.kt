package io.paritytech.polkadotapp.feature_products_impl.domain.truapi

import io.paritytech.polkadotapp.feature_products_impl.presentation.productBotManagement.ProductsRouter
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull
import javax.inject.Inject
import javax.inject.Singleton

/**
 * One person the user may hand to a product.
 *
 * Carries the account so the answer needs no second lookup, and a name only for
 * the row to read; a contact the app has no name for is still pickable.
 */
class ContactPickOption(
    val account: ByteArray,
    val displayName: String?,
)

/** One in-flight pick and the choice the core is waiting on. */
class TrUAPIContactPickContext(
    val productId: String,
    val options: List<ContactPickOption>,
) {
    private val choice = CompletableDeferred<ContactPickOption?>()
    private val shown = CompletableDeferred<Unit>()

    /** Called by the sheet once it holds this context. */
    fun markShown() {
        shown.complete(Unit)
    }

    /** Whether the sheet appeared within [timeoutMs]. */
    suspend fun awaitShown(timeoutMs: Long): Boolean = withTimeoutOrNull(timeoutMs) { shown.await() } != null

    fun pick(option: ContactPickOption) {
        choice.complete(option)
    }

    /** Also the answer for a dismissed sheet, so an abandoned pick names nobody. */
    fun dismiss() {
        choice.complete(null)
    }

    suspend fun await(): ContactPickOption? = choice.await()
}

/**
 * Parks the in-flight pick for the sheet to pick up.
 *
 * Mirrors [TrUAPIConfirmationContextHolder], owner-guarded clear included: the
 * sheet's ViewModel is cleared after the dismiss animation, by which time the
 * holder may already carry the next request.
 */
@Singleton
class TrUAPIContactPickContextHolder @Inject constructor() {
    private var context: TrUAPIContactPickContext? = null

    fun set(context: TrUAPIContactPickContext) {
        this.context = context
    }

    fun get(): TrUAPIContactPickContext? = context

    fun clear(owner: TrUAPIContactPickContext) {
        if (context === owner) {
            context = null
        }
    }
}

/** Opens the contact picker for a product and awaits the person the user chose. */
// Singleton for the same reason the confirmation launcher is: the holder carries
// one context, and every live tab's bridge shares it.
@Singleton
class TrUAPIContactPickLauncher @Inject constructor(
    private val holder: TrUAPIContactPickContextHolder,
    private val productsRouter: ProductsRouter,
) {
    private val oneAtATime = Mutex()

    suspend fun awaitPick(
        productId: String,
        options: List<ContactPickOption>,
    ): ContactPickOption? = oneAtATime.withLock {
        val context = TrUAPIContactPickContext(productId, options)
        holder.set(context)
        productsRouter.openTrUAPIContactPick()
        // Navigation can fail silently (backgrounded, no controller, another
        // sheet on top), and then no ViewModel ever answers. Waiting on that
        // would hold the lock, and every later pick, forever. The context stays
        // in the holder so a sheet that does turn up late still finds one.
        if (!context.awaitShown(SHEET_SHOWN_TIMEOUT_MS)) {
            context.dismiss()
            return@withLock null
        }
        context.await()
    }

    private companion object {
        const val SHEET_SHOWN_TIMEOUT_MS = 10_000L
    }
}
