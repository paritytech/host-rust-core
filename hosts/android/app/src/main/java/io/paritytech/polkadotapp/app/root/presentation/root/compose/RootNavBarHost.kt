package io.paritytech.polkadotapp.app.root.presentation.root.compose

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavController
import io.paritytech.polkadotapp.app.root.presentation.root.RootNavBarViewModel

/**
 * Self-contained host for the global navigation bar: resolves its own [RootNavBarViewModel] and renders
 * the overlay. The activity only needs to place this in a ComposeView — no bar wiring lives there. The
 * [navController]'s current entry is the "screen entered" signal the bar resets its posture on.
 */
@Composable
fun RootNavBarHost(navController: NavController) {
    val viewModel: RootNavBarViewModel = hiltViewModel()

    val hidden by viewModel.hidden.collectAsStateWithLifecycle()
    val forceShown by viewModel.forced.collectAsStateWithLifecycle()
    val currentEntry by navController.currentBackStackEntryFlow.collectAsStateWithLifecycle(initialValue = null)
    val currentTab by viewModel.currentTab.collectAsStateWithLifecycle()
    val tabWarnings by viewModel.tabWarnings.collectAsStateWithLifecycle()
    val openApps by viewModel.openApps.collectAsStateWithLifecycle()
    val tooltipVisible by viewModel.isScannerTooltipVisible.collectAsStateWithLifecycle()

    RootNavBarOverlay(
        hidden = hidden,
        forceShown = forceShown,
        screenKey = currentEntry?.id,
        currentTab = currentTab,
        tabWarnings = tabWarnings,
        openApps = openApps,
        scannerTooltipVisible = tooltipVisible,
        onTabSelected = viewModel::onTabSelected,
        onScanClicked = viewModel::openScanner,
        onScannerTooltipDismiss = viewModel::dismissScannerTooltip,
        onAppClick = viewModel::onAppClick,
        onAppClose = viewModel::onAppClose,
        onOffset = viewModel::setBarOffset,
        onBarHeight = viewModel::setBarHeight,
    )
}
