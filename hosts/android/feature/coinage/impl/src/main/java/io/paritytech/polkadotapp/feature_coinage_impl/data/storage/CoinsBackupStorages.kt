package io.paritytech.polkadotapp.feature_coinage_impl.data.storage

import io.paritytech.polkadotapp.common.data.storage.SingleValueStorage
import io.paritytech.polkadotapp.common.data.storage.SingleValueStorageFactory
import io.paritytech.polkadotapp.common.data.storage.preferences.store.PreferencesSingleValueSerializer
import javax.inject.Inject

interface CoinsInitialBackupCompletedStorage : SingleValueStorage<Boolean>

class RealCoinsInitialBackupCompletedStorage @Inject constructor(
    factory: SingleValueStorageFactory,
) : CoinsInitialBackupCompletedStorage,
    SingleValueStorage<Boolean> by factory.preferences(
        key = "CoinsInitialBackupCompletedStorage",
        serializer = PreferencesSingleValueSerializer.from(
            toString = { it.toString() },
            fromString = { it.toBoolean() },
        ),
        default = false,
    )

interface CoinsDeepBackupCompletedStorage : SingleValueStorage<Boolean>

class RealCoinsDeepBackupCompletedStorage @Inject constructor(
    factory: SingleValueStorageFactory,
) : CoinsDeepBackupCompletedStorage,
    SingleValueStorage<Boolean> by factory.preferences(
        key = "CoinsDeepBackupCompletedStorage",
        serializer = PreferencesSingleValueSerializer.from(
            toString = { it.toString() },
            fromString = { it.toBoolean() },
        ),
        default = false,
    )

interface CoinsBackupLastIndexStorage : SingleValueStorage<Int>
class RealCoinsBackupLastIndexStorage @Inject constructor(
    factory: SingleValueStorageFactory,
) : CoinsBackupLastIndexStorage,
    SingleValueStorage<Int> by factory.preferences(
        key = "CoinsBackupLastIndexStorage",
        serializer = PreferencesSingleValueSerializer.from(
            toString = { it.toString() },
            fromString = { it.toInt() },
        ),
        default = 0,
    )
