package io.paritytech.polkadotapp.feature_products_impl.domain.worker

import java.lang.ref.WeakReference

/**
 * A mutable, thread-safe holder for a modality-specific API bound onto a shared worker (e.g. chat
 * messaging). Set when a driver attaches, cleared when it detaches. The value is held weakly so a
 * live worker never keeps its driver alive, and read once per call so a concurrent rebind cannot
 * tear a partially updated pair.
 */
interface ModalityApiSlot<T : Any> {
    fun set(value: T)
    fun clear()
    fun tryUse(): Result<T>
}

class WeakModalityApiSlot<T : Any> : ModalityApiSlot<T> {
    @Volatile
    private var ref: WeakReference<T>? = null

    override fun set(value: T) {
        ref = WeakReference(value)
    }

    override fun clear() {
        ref = null
    }

    override fun tryUse(): Result<T> {
        val value = ref?.get() ?: return Result.failure(EmptyModalitySlot)
        return Result.success(value)
    }

    private object EmptyModalitySlot : Exception("No modality API is bound")
}
