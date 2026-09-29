package io.paritytech.polkadotapp.chains.storage.source.query.intercept

import javax.inject.Inject
import javax.inject.Singleton

/**
 * Indexes the multibound [StorageQueryInterceptor] set by [StorageTarget] once at construction, so each storage
 * read costs a single map lookup: a miss returns the raw value/flow untouched, a hit yields only the interceptors
 * registered for that entry.
 */
@Singleton
class StorageInterceptorRegistry @Inject constructor(
    interceptors: Set<@JvmSuppressWildcards StorageQueryInterceptor>,
) {
    private val interceptorsByTarget: Map<StorageTarget, List<StorageQueryInterceptor>> =
        interceptors
            .flatMap { interceptor -> interceptor.targets.map { target -> target to interceptor } }
            .groupBy(keySelector = { it.first }, valueTransform = { it.second })

    fun forTarget(module: String, storage: String): List<StorageQueryInterceptor> {
        return interceptorsByTarget[StorageTarget(module, storage)].orEmpty()
    }
}
