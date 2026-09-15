package io.paritytech.polkadotapp.feature_coinage_impl.data.storage

import io.paritytech.polkadotapp.common.data.storage.SingleValueStorage
import io.paritytech.polkadotapp.common.data.storage.SingleValueStorageFactory
import io.paritytech.polkadotapp.common.data.storage.preferences.store.PreferencesSingleValueSerializer
import javax.inject.Inject

interface VouchersInitialBackupCompletedStorage : SingleValueStorage<Boolean>

class RealVouchersInitialBackupCompletedStorage @Inject constructor(
    factory: SingleValueStorageFactory,
) : VouchersInitialBackupCompletedStorage,
    SingleValueStorage<Boolean> by factory.preferences(
        key = "VouchersInitialBackupCompletedStorage",
        serializer = PreferencesSingleValueSerializer.from(
            toString = { it.toString() },
            fromString = { it.toBoolean() },
        ),
        default = false,
    )

interface VouchersDeepBackupCompletedStorage : SingleValueStorage<Boolean>

class RealVouchersDeepBackupCompletedStorage @Inject constructor(
    factory: SingleValueStorageFactory,
) : VouchersDeepBackupCompletedStorage,
    SingleValueStorage<Boolean> by factory.preferences(
        key = "VouchersDeepBackupCompletedStorage",
        serializer = PreferencesSingleValueSerializer.from(
            toString = { it.toString() },
            fromString = { it.toBoolean() },
        ),
        default = false,
    )

interface VouchersBackupLastIndexStorage : SingleValueStorage<Int>

class RealVouchersBackupLastIndexStorage @Inject constructor(
    factory: SingleValueStorageFactory,
) : VouchersBackupLastIndexStorage,
    SingleValueStorage<Int> by factory.preferences(
        key = "VouchersBackupLastIndexStorage",
        serializer = PreferencesSingleValueSerializer.from(
            toString = { it.toString() },
            fromString = { it.toInt() },
        ),
        default = 0,
    )
