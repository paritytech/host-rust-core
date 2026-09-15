package io.paritytech.polkadotapp.feature_account_impl.presentation.address.mixin

import io.paritytech.polkadotapp.common.presentation.search.withMapSearching
import io.paritytech.polkadotapp.common.presentation.ui.mixin.paste.PasteMixin
import io.paritytech.polkadotapp.common.utils.shareInBackground
import io.paritytech.polkadotapp.feature_account_api.presentation.address.mixin.AddressInputMixin
import io.paritytech.polkadotapp.feature_account_api.presentation.address.model.ExtractedAddressesCategory
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow

internal class RealAddressInputMixin(
    private val pasteMixinFactory: PasteMixin.Factory,
    private val addressConverters: List<AddressInputMixin.AddressConverter>,
    private val coroutineScope: CoroutineScope,
) : AddressInputMixin,
    CoroutineScope by coroutineScope {
    override val paste: PasteMixin = pasteMixinFactory.create {
        input.value = it
    }

    override val input: MutableStateFlow<String> = MutableStateFlow("")

    override val addressCandidates = input
        .withMapSearching { convertInputToAddresses(it) }
        .shareInBackground()

    private suspend fun convertInputToAddresses(input: String) =
        runCatching {
            val allSections = addressConverters
                .mapNotNull {
                    runCatching {
                        it.convertToAddress(input)
                    }.getOrNull()
                }

            val (generalSections, customSections) = allSections.partition { it.category == ExtractedAddressesCategory.General }
            val allGeneralAddresses = generalSections.flatMap { it.addresses }

            buildMap {
                customSections.forEach {
                    put(it.category, it.addresses)
                }

                put(ExtractedAddressesCategory.General, allGeneralAddresses)
            }
        }
}
