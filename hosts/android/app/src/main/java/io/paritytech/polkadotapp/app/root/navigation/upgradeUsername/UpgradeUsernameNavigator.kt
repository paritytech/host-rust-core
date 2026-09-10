package io.paritytech.polkadotapp.app.root.navigation.upgradeUsername

import io.paritytech.polkadotapp.app.root.navigation.BaseNavigator
import io.paritytech.polkadotapp.app.root.navigation.NavigationHolder
import io.paritytech.polkadotapp.feature_upgrade_username_impl.presentation.UpgradeUsernameRouter
import javax.inject.Inject

class UpgradeUsernameNavigator @Inject constructor(
    navigationHolder: NavigationHolder,
) : BaseNavigator(navigationHolder), UpgradeUsernameRouter
