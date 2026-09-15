package io.paritytech.polkadotapp.feature_products_impl.presentation.permissionPrompt.di

import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.components.ViewModelComponent
import io.paritytech.polkadotapp.feature_products_impl.domain.permissions.PermissionContextHolder
import io.paritytech.polkadotapp.feature_products_impl.domain.permissions.ProductPermissionContext

@Module
@InstallIn(ViewModelComponent::class)
class PermissionPromptModule {
    @Provides
    fun providePermissionContext(
        holder: PermissionContextHolder,
    ): ProductPermissionContext {
        return requireNotNull(holder.get()) {
            "ProductPermissionContext is not set. The permission prompt was likely restored after process death."
        }
    }
}
