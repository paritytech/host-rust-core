package io.paritytech.polkadotapp.feature_wallet_impl.presentation.sendPayment

import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.design.components.avatar.AvatarUiModel
import io.paritytech.polkadotapp.design.configs.colors.AvatarColorScheme
import io.paritytech.polkadotapp.feature_account_api.presentation.address.model.ExtractedAddress
import io.paritytech.polkadotapp.feature_account_api.presentation.address.model.ExtractedAddressesCategory
import kotlinx.collections.immutable.toImmutableList
import io.paritytech.polkadotapp.common.R as RCommon

internal fun Map<ExtractedAddressesCategory, List<ExtractedAddress>>.toSearchSections(): List<PaymentSearchSectionUiModel> {
    val shownAccountIds = mutableSetOf<AccountId>()

    return mapNotNull { (category, addresses) ->
        val sectionAddresses = addresses
            .distinctByAccountId()
            .filterNot { it.accountId in shownAccountIds }

        shownAccountIds += sectionAddresses.map { it.accountId }

        if (sectionAddresses.isEmpty()) {
            null
        } else {
            PaymentSearchSectionUiModel(
                key = category.sectionKey(),
                titleRes = category.titleRes(),
                items = sectionAddresses.map { it.toUi() }.toImmutableList()
            )
        }
    }
}

private fun List<ExtractedAddress>.distinctByAccountId(): List<ExtractedAddress> {
    return groupBy { it.accountId }
        .values
        .map { group -> group.find { it.type == ExtractedAddress.DisplayType.USERNAME } ?: group.first() }
}

private fun ExtractedAddressesCategory.sectionKey(): String {
    return when (this) {
        ExtractedAddressesCategory.General -> "general"
        is ExtractedAddressesCategory.Custom -> "custom_$labelRes"
    }
}

private fun ExtractedAddressesCategory.titleRes(): Int {
    return when (this) {
        ExtractedAddressesCategory.General -> RCommon.string.send_payment_section_global_search
        is ExtractedAddressesCategory.Custom -> labelRes
    }
}

private fun ExtractedAddress.toUi(): PaymentSearchResultUiModel {
    return PaymentSearchResultUiModel(
        extractedAddress = this,
        avatarModel = AvatarUiModel.Name(
            name = display,
            colorScheme = AvatarColorScheme.from(accountId.value)
        ),
    )
}
