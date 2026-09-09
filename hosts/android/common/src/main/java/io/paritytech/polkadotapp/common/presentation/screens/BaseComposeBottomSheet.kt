package io.paritytech.polkadotapp.common.presentation.screens

import android.app.Dialog
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.bottomsheet.BottomSheetBehavior.STATE_EXPANDED
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.bottomsheet.BottomSheetDialogFragment
import io.paritytech.polkadotapp.common.R
import io.paritytech.polkadotapp.common.presentation.notification.AppNotifier
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import javax.inject.Inject

abstract class BaseComposeBottomSheet<T : BaseViewModel> : BottomSheetDialogFragment() {
    abstract val viewModel: T

    // Injected into every @AndroidEntryPoint subclass.
    @Inject
    lateinit var appNotifier: AppNotifier

    protected val bottomSheetBehavior: BottomSheetBehavior<*>?
        get() = (dialog as? BottomSheetDialog)?.behavior

    @Composable
    protected abstract fun Screen()

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog =
        object : BaseBottomSheetDialog(requireContext(), R.style.ComposeBottomSheetDialog) {}
            .apply {
                behavior.apply {
                    skipCollapsed = true
                    state = STATE_EXPANDED
                }
            }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ) = ComposeView(requireContext()).apply {
        layoutParams = LayoutParams(MATCH_PARENT, WRAP_CONTENT)

        setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnViewTreeLifecycleDestroyed)

        setContent {
            PolkadotTheme {
                Box(
                    modifier = Modifier.semantics { testTagsAsResourceId = true }
                ) {
                    ObserveViewModelEvents(viewModel, appNotifier)

                    Screen()
                }
            }
        }
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        (view.parent as? View)?.setBackgroundResource(0)
    }
}
