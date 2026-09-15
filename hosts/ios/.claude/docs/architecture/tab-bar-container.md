# Tab Bar Container

`MainTabBarViewController` is a plain `UIViewController` that owns tab switching itself, replacing `UITabBarController` so the bar could match the Figma spec and support drag-across-tabs. Switching cross-fades outgoing and incoming views over 150 ms (`TabBarContainer.mount`, animated switches only).

The container mounts **either a tab or an SPA browser tab** — `TabBarContentSelection` is `.tab(Int)` or `.spa(UUID)`. An SPA is a peer of the tabs, not a child of one, so it is not pushed or presented; see [SPA Hosting](#spa-hosting).

**`tabBarController` is `nil` everywhere.** Code reaching for it is dead. For the visible screen use `UIWindow.keyWindow?.topmostViewController`, which descends through `TopmostChildProviding`. To reach the container itself use `UIApplication.shared.mainTabBarController`.

## Where Things Live

| Thing | Location |
|---|---|
| Container controller | `polkadot-app/Modules/MainTabBar/MainTabBarViewController.swift` |
| Child mounting | `polkadot-app/Modules/MainTabBar/Container/TabBarContainer.swift` |
| Tab-vs-SPA selection | `polkadot-app/Modules/MainTabBar/Container/TabBarContentSelection.swift` |
| `hidesBottomBarWhenPushed` resolution | `polkadot-app/Modules/MainTabBar/Container/TabBarHiddenPolicy.swift` |
| Re-tap behaviour | `polkadot-app/Modules/MainTabBar/Container/TabBarReselectionPolicy.swift` |
| Scroll-to-top target search | `polkadot-app/Modules/MainTabBar/Container/TabBarScrollToTopLocator.swift` |
| Fold state machine | `polkadot-app/Modules/MainTabBar/Chrome/TabBarVisibilityPolicy.swift` |
| Bar, widgets and safe-area insets | `polkadot-app/Modules/MainTabBar/Chrome/TabBarBottomChromeController.swift` |
| Chrome apply input | `polkadot-app/Modules/MainTabBar/Chrome/TabBarChromeContext.swift` |
| Panel kinds | `polkadot-app/Modules/MainTabBar/Chrome/TabBarPanelKind.swift` |
| Bar view and its parts | `Packages/PolkadotUI/Sources/Components/DSTabBar/` |
| Row geometry (`DSTabBarRow`) | `Packages/PolkadotUI/Sources/Components/DSTabBar/DSTabBarGeometry.swift` |
| Centre slot geometry / state | `Packages/PolkadotUI/Sources/Components/DSTabBar/DSTabBarCentreSlot.swift` |
| Centre slot view | `.../DSTabBar/DSTabBarCentreSlotView.swift`, `DSTabBarTabsGlyphView.swift` |
| Tabs panel | `.../DSTabBar/DSTabBarTabsPanelView.swift`, `DSTabBarPanelLayout.swift`, `DSTabBarChipView.swift` |
| Trailing slot and content panel | `.../DSTabBar/DSTabBarTrailingSlot.swift`, `DSTabBarContentPanelView.swift` |
| Top status strip view | `Packages/PolkadotUI/Sources/Modules/MainTabBar/ChainConnectionStatusBarView.swift` |
| Chrome glass surface | `Packages/PolkadotUI/Sources/Components/DSGlassBackground/` |
| SPA tab store and controller pool | `polkadot-app/Modules/Browser/` |
| SPA chip view models | `polkadot-app/Modules/MainTabBar/SPATabChipViewModel.swift` |
| Placeholder trailing content | `polkadot-app/Modules/MainTabBar/TabBarPanelPlaceholderContent.swift` |
| `topmostViewController` | `Packages/UIKitExt/Sources/UIWindow/UIWindow+keyWindow.swift` |
| `mainTabBarController` | `polkadot-app/Common/Extension/UIApplication+MainContainer.swift` |

## Fold State

`.shown` is the full capsule; `.folded` is a leading-edge sliver, tappable to restore. `TabBarVisibilityPolicy.state(isTabRoot:derived:override:)` resolves in order **under `FEATURE_PRODUCTS` (DevCI, Nightly)**:

1. Tab root → `.shown`. **A tab root can never fold.**
2. A recorded per-screen user override wins.
3. Otherwise `foldDerived`.

Overrides live in `screenOverrides`, weakly keyed on `navigationScreen`, so folding one pushed screen does not leak to another.

**Under `!FEATURE_PRODUCTS` (Release)**, steps 2 and 3 never run — every non-root screen resolves to `.hidden` regardless of `override` or `foldDerived`.

Nothing hides the bar programmatically — presented view controllers cover it structurally. Both LocalAuth screens are transparent by design, so the bar stays *visible* behind re-auth but untappable, since the presentation owns the touch.

## Bar Visibility

**Under `FEATURE_PRODUCTS`, the bar folds when *any* controller at or below the target sets `hidesBottomBarWhenPushed`, not just the top one.** `UITabBarController` behaved this way and screens rely on it. `TabBarHiddenPolicy.deriveFoldState(in:showing:)` scans `stack[...targetIndex].dropFirst()`; the root is excluded, so a tab root setting the flag does not fold.

**Under `!FEATURE_PRODUCTS`, every non-root screen is `.hidden` regardless of the `hidesBottomBarWhenPushed` flag**, so this scan has no effect there.

`stackAfterCancelledPop(stack:staying:)` covers the window where UIKit has already mutated `viewControllers` but the transition is reversing — a cancelled pop restores the *staying* screen's state, not the target's.

## Safe Area

Two insets stack at the bottom and go on **different** controllers so they compose instead of overwriting. They are unchanged by the top status strip and still go on the two child controllers below; **the top inset is the only inset the container writes on itself** — a constant, set once (see [Top Status Strip](#top-status-strip)).

| Inset | Applied to |
|---|---|
| Bar clearance | the tab's `UINavigationController` — or the tab controller itself when there is none (Scan) |
| Widget height | that nav's `topViewController` — summed onto the tab controller when there is no nav |

Split because they change at different rates — the nav controller is stable for the tab's lifetime, widget height follows the top screen. `updateContentSafeAreaInset()` zeroes the previously-adjusted controller before writing the new one.

`occupiedHeight` is `DSTabBarView.preferredHeight()` on a tab root, the raw bottom safe-area inset elsewhere; `contentClearance` is `occupiedHeight` minus that inset, floored at 0. Neither reads fold state — both depend only on `isTabRoot`.

**Under `FEATURE_PRODUCTS`, clearance is contributed only on a tab root**, which is narrower than the bar being `.shown`. Off the root a screen can show the full capsule — no override, no fold requested — while reserving zero space, so the bar floats over its bottom content and swallows touches in the capsule rect. Pushed screens should either set `hidesBottomBarWhenPushed` or keep interactive content clear of the bottom.

**Under `!FEATURE_PRODUCTS`, non-root screens are always `.hidden`, so clearance ⟺ tab root ⟺ `.shown`** — the bar cannot float over pushed screen content or swallow touches, and the advice to pushed screens does not apply. `contributesClearance(isTabRoot:)` itself is unchanged and correct in both arms.

### `apply` vs `applyLayout`

- `apply(_:animatingAlongside:)` sets the fold inputs (`isTabRoot`, `stackFolds`, `navigationScreen`), retargets, then `refresh()` resolves and animates the fold.
- `applyLayout(_:animatingAlongside:)` retargets only, leaving fold inputs untouched.

**Mid-gesture, use `applyLayout`.** An interactive pop drives the fold through `setFoldProgress`; a full `apply` would let `refresh()` snap the bar and fight the gesture. `track(of:showing:animated:)` calls `applyLayout` while interactive, `apply` once `notifyWhenInteractionChanges` settles.

`viewSafeAreaInsetsDidChange()` and `TabBarContainer`'s `onContentInsetInvalidated` also use `applyLayout`, re-deriving from `container.selectedController` instead of reusing the chrome's last-applied targets — reusing them let a late `didShow` from a background tab pin insets to a controller no longer visible. Fold inputs are still set only by `apply`, unchecked against the selected tab; no known live path, since `ModuleNavigator` selects the tab before navigating.

`updateLayout` no-ops while the chrome's view has no window — a `.fullScreen` presentation elsewhere detaches it, where `safeAreaInsets` reads zero and clearance would compute too large. Last-applied insets hold until reattachment fires `viewSafeAreaInsetsDidChange`.

## Top Status Strip

A permanent 20pt strip at the top of `MainTabBarViewController` holds one `ChainStatusRingView` per chain — the **same view the bottom content panel uses** — for the same three `ChainConnectionTarget`s (chat, bulletin, assethub). There is no visible chain name. **The strip is informational only**: no tap handling, no fold, no hide, constant height, and it ships in both `FEATURE_PRODUCTS` arms.

The chain name and state survive only as the ring's accessibility label, which the ring owns (see [Shipped content](#shipped-content--chain-connection-status)).

`installStatusBar()` writes `additionalSafeAreaInsets.top = ChainConnectionStatusBarView.preferredHeight` on **the container itself**, once, in `viewDidLoad`. It is a constant and is never recomputed in `viewSafeAreaInsetsDidChange`. UIKit propagates the combined inset (system top + 20) down through each mounted nav controller to every screen it pushes, so **a pushed screen inherits the clearance with no bookkeeping**.

**There is one view, not two**: the `UIHostingController`'s, added straight to the container view with leading, trailing and **bottom pinned to `view.safeAreaLayoutGuide.snp.top`** — that guide already includes the 20pt once the inset is set, so the host occupies exactly the band the inset reserved. **No height constraint**; height comes from the SwiftUI view's own `.frame(height: Self.preferredHeight)` as intrinsic content size. The host's `backgroundColor` is `.clear` — **the strip paints no fill of its own**. What shows behind the system status bar and behind the icons is the container's own `.bgSurfaceMain`.

**Install order in `viewDidLoad` is load-bearing.** `installStatusBar()` runs *before* `installChromeController()` so the bottom chrome stays topmost, and mounted tab children insert at subview index 0 so they stay behind the strip. `TabBarContainer` is unchanged — children still mount full-bleed into the container's own view.

*Rationale:* the obvious alternative — pinning a dedicated content container view below the strip and mounting children into it — physically moves the child's frame out of the top safe area, so UIKit computes the child's `safeAreaInsets.top` as 0 and a `UINavigationBar` stops drawing its background at the container's top edge instead of extending to y=0. Applying the inset per tab controller from the chrome was also rejected: it needs the same "which controller is current" tracking the chrome already does for the bottom, in a second owner.

**Content flow.** `MainTabBarPresenter.didReceiveChainStatus` pushes to two hosts. `view?.showChainStatus(rows)` is called *outside* the `#if !FEATURE_PRODUCTS`; the existing `showTabBarPanelContent` call stays inside it. The strip takes raw `[ChainConnectionStatusViewModel]`, not a `HashableContentConfiguration`, because its host is a `UIHostingController` rather than a `UIContentView` — exactly the case the provider's row-emitting contract anticipates, with the presenter wrapping at its own push site. The view controller assigns `statusBarHost.rootView`.

**The strip forced sampling to go app-wide.** `ChainStatusProvider` used to gate its two sampling siblings behind a panel-visibility signal — `onPanelChanged` → `didChangeContentPanelVisibility` → `setChainStatusActive` → `setActive`. A permanent strip means there is no longer a moment when nobody is displaying latency or block freshness, so the gate had no state left to express and **the whole chain was deleted**: `ChainStatusProviding.setActive`, `MainTabBarInteractorInputProtocol.setChainStatusActive`, `MainTabBarPresenterProtocol.didChangeContentPanelVisibility` and the `onPanelChanged` assignment are all gone. Activation now happens once from `ChainStatusProvider.start()`, called by `ServiceCoordinator.setup()`, which guards on `!isObserving` and spawns a `Task` awaiting `setActive(true)` on both siblings; `statusStream()` is a pure `nonisolated` accessor that starts nothing.

*Cost, accepted deliberately:* a 30 s `system_health` probe per chain and three `subscribeNewHeads` subscriptions now run for the app's lifetime in **every** arm, where before they ran only while the peek panel was open. `ServiceCoordinator.throttle()` still does not reach them. This is what buys the strip a real ping colour instead of a permanently un-sampled grey dot.

*Accepted:*

- A child that ignores its safe area and paints to y=0 (a chat background, an SPA web view) **shows through the strip**, behind the icons — mounted children sit at subview index 0, below the clear host, and nothing masks them.
- `availablePanelHeight` in the chrome subtracts `view.safeAreaInsets.top`, which now includes the strip, so the tabs and content panels open 20pt shorter.
- Nav bars shift down 20pt on every screen; their background still stretches to y=0, visible behind the strip's icons.

## Re-tap

`TabBarReselectionPolicy.action(for:)`, in order: modal presented on the target → `.ignore`; stack deeper than its root → `.popToRoot`; otherwise `.scrollToTop`.

Pop-to-root matches `UITabBarController`. Scroll-to-top is the addition and fires only at the tab root, so returning from a detail screen preserves the root's scroll position. `TabBarScrollToTopLocator` picks the scroll view heuristically — visible area, vertical scrollability, depth. A screen cannot opt in or nominate one.

## Selection Gesture

`DSTabSelectionRecognizer` tracks a single touch beginning anywhere `DSTabBarView.hitTest` claims — the capsule only. The folded bar's tap target lives on `TabBarChromePassthroughView`, which is full-bleed and can receive touches at the screen edge that the inset container cannot; a tap there routes through `setUserOverride(.shown,)`, the same path `onFoldChangeRequested` uses. The recognizer cancels once vertical travel exceeds `DSTabBarMetrics.selectionCancelVerticalSlop`; horizontal travel never cancels, since it drives drag-across-tabs (clamped by `DSTabBarGeometry.clampedPillOriginX`).

Touch-to-item resolution is now `resolvedTarget(atX:) -> DSTabBarTouchTarget` (`.item(Int)` or `.trailing`), tested in order: trailing slot frame, centre slot, then nearest item. A press beginning on the trailing slot creates no `dragState`, so the lens never lifts or parks there. Only `.item` taps can drag or perform selection; `.trailing` fires `onTrailingSlotTapped` in the `.ended / .select` branch, guarded by `!isFolded` to match the `.began` phase.

Cancelling does *not* hand the touch to the scroll view underneath — UIKit hit-tests once at `touchesBegan`, not on every move.

**Two accepted gaps**, reviewed and kept deliberately — neither is an undiscovered bug:

- A short, fast vertical flick stays under the slop and `DSTabBarFoldDecision.decideFromShown` tests `velocityX`, so it falls through to `.select`. On the selected tab of a deep stack that reaches `popToRoot`.
- A wide drag-across-tabs whose arc deviates past the slop cancels itself mid-drag.

They are coupled — raising the slop widens the second, lowering it widens the first. Decoupling needs an axis-relative test: cancel only when vertical travel both exceeds the slop and dominates horizontal.

## Centre Slot

When at least one SPA browser tab is open (`DSTabBarView.spaTabCount > 0`), the **centre item widens to a double-width slot** split into two halves: QR (Scan) on the left, an open-tabs glyph on the right, separated by a hairline divider.

Layout comes from `DSTabBarRow`, which replaced the free functions on `DSTabBarGeometry`. The row divides its width into *units*, not items: `unitCount == itemCount + (isCentreExpanded ? 1 : 0) + (hasTrailingSlot ? 1 : 0)`, and the centre item spans two units. `centreIndex` is `itemCount / 2` — the centre is positional, so it follows the tab list rather than naming `.scan`. **`centreIndex` does not account for the trailing slot,** so it remains at the geometric mid-point of items alone. Consequence: the centre slot is no longer at the capsule's optical centre when the trailing slot is visible. This is accepted.

All widths stay derived; nothing is hardcoded per tab count. `itemFrame(at:)` and `trailingSlotFrame` both dispatch to a shared private `unitFrame(atUnitIndex:span:)`.

The real `DSTabBarItemView` at `centreIndex` is hidden while expanded and `DSTabBarCentreSlotView` draws both halves instead. That view is **not interactive** — the existing `DSTabSelectionRecognizer` still owns the touch. `resolvedTarget(atX:)` returns `.item(centreIndex)` for any x inside the slot (bypassing nearest-centre search, which would otherwise split the wide slot between neighbours), and on `.select` `DSTabBarCentreSlot.half(atX:inSlot:)` decides which half fired. A QR half-tap falls through to normal selection; a tabs half-tap reports via `onCentreHalfTapped` and returns without committing selection.

Active state is derived, not stored twice — `isTabsActive = isPanelOpen || isSPAMounted`, and `isQRActive = isQRSelected && !isTabsActive`. While tabs is active the selection lens **parks on the centre slot** (`isCentreLensParked`) regardless of which tab is actually selected, and the selected tab's accessibility element drops its `.selected` trait to match.

Expanding or collapsing the slot reflows the whole row; `animateRowReflow()` sets `animatesLensOnNextLayout` so the lens springs with the reflow instead of jumping in `layoutSubviews`.

## Glass Container

`DSGlassContainerView` owns exactly one `DSGlassBackgroundView` surface; the chrome content (bar, panel, widgets) lives inside that surface's `contentView`. No `UIGlassContainerEffect` or merge/spacing tuning.

The container is constrained to the capsule's geometry: centred, `width <= 500`, `width == superview - 21*2` at `.high`. `DSTabBarView` lays out against its own bounds and no longer insets via `DSTabBarGeometry.capsuleFrame`.

One `.capsule` shape serves both states: a true capsule at 62pt tall when collapsed, clamped to the same radius when the panel expands the container. No state-dependent shape switching.

*Rationale:* Apple's guidance (WWDC 2025 session 284, "Build a UIKit app with the new design") is that glass elements should not overlap — one floating layer, not several merged shapes. Pre-iOS 26, the same surface renders blur + tinted substrate + border + shadow as a single material; the old `setCapsuleGlassHidden` workaround is gone.

## Tabs Panel and Content Panel

`DSTabBarTabsPanelView` holds open-SPA chips in a scroll view with no background of its own; installed by `TabBarBottomChromeController` and pinned `bottom == barView.top` with `leading/trailing.equalToSuperview()` to fill the container horizontally. Chips are a fixed 5-column grid (`DSTabBarPanelLayout`); height is `min(contentHeight + capsuleHeight, availableHeight)` since the container stacks the panel and the capsule.

- Long-press a chip → context menu with Close (`onChipCloseRequested`).
- Tap a chip → mount that SPA and close the panel.
- `.spaTabs` panel closes on: outside tap, tab selection, `select(tab:)`, fold to `.folded`, chip list emptying, or no available height.

The outside tap is why `TabBarChromePassthroughView` is no longer purely passthrough: while any panel is open it claims self-hits (`isOutsideTapEnabled`) so the recognizer can fire. The recognizer's delegate accepts only touches landing on the chrome view itself, so bar and widget touches are unaffected. The passthrough view also carries the fold grab zone and checks it *before* the outside-tap flag, so a folded bar unfolds rather than closing a panel.

Chips reuse views across updates — `setChips` rebuilds only when the id sequence changes, otherwise it re-applies in place, and `DSTabBarChipView.apply` skips icon reload when the id is unchanged. The "chips empty or no available height" auto-close is guarded on `openPanel == .spaTabs` so it does not close an unrelated content panel on SPA mount/unmount.

### Trailing Slot and Content Panel

The row now has an optional trailing chrome button as its last unit. `DSTabBarRow.hasTrailingSlot` joins `isCentreExpanded` in the unit count: `unitCount == itemCount + (isCentreExpanded ? 1 : 0) + (hasTrailingSlot ? 1 : 0)`. Both item and trailing frames derive from `unitFrame(atUnitIndex:span:)`.

`row.draggableWidth` is `trailingSlotFrame?.minX ?? width`, the boundary that `clampedPillOriginX` clamps against, so a drag-across-tabs cannot park the selection pill on the trailing button.

The trailing slot is drawn as a plain template `UIImageView` in `lens.contentView` — no dedicated slot view, unlike the centre slot, because it has no divider or live glyph to own. Tint is `.fgPrimary` while its panel is open, `.fgSecondary` otherwise, refreshed on `DSThemeTrait` changes. A press on it creates no drag state, so the lens never lifts; only the `.ended / .select` branch fires `onTrailingSlotTapped`, guarded by `!isFolded`.

Panel state is now `TabBarBottomChromeController.openPanel: TabBarPanelKind?` (`.spaTabs` / `.content`), replacing separate `isPanelOpen` booleans. Both panels' `setOpen` run through one animator, so closing one panel is automatic when opening another — exclusivity is structural. `setPanel(_:animated:)` replaces the old two-call pattern.

`DSTabBarContentPanelView` hosts any `HashableContentConfiguration` via `makeContentView()` — the same seam `AppWidgetContentViewController` uses — and reuses the content view when `defaultReuseIdentifier` is unchanged. It knows nothing about the content. Content must be self-sizing: height is `systemLayoutSizeFitting` clamped by `DSTabBarPanelLayout.panelHeight(contentHeight:availableHeight:)` (same layout the chips use), and it returns `capsuleHeight` when it has no configuration or no width yet.

Content ownership: `MainTabBarPresenter` pushes a configuration through `MainTabBarViewProtocol.showTabBarPanelContent(_:)`; the view controller builds the `DSTabBarTrailingSlot` (SF Symbol `point.3.connected.trianglepath.dotted`, label from `TabBarTrailingSlot`) and calls `chromeController.setTrailingPanel(slot:content:)`. No configuration means no trailing unit at all and the row reflows — same treatment the centre slot gets when `spaTabCount` crosses 0.

**Shipped content — chain connection status.** The panel holds one column per `ChainConnectionTarget` (chat, bulletin, assethub) in a single `HStack`, rendered by `ChainConnectionStatusView` in `PolkadotUI`: the chain name in `.caption12Regular()` / `.fgSecondary` above a 40pt `ChainStatusRingView`, each column `maxWidth: .infinity` so the three split the panel evenly. No numbers — the ring carries every measurement. The top strip hosts the same ring at its default size and **without a name** (see [Top Status Strip](#top-status-strip)), so this is the one place the ring is described. Each ring carries two facts:

| element | carries | rendering |
|---|---|---|
| arc length | block freshness | `1 - min(age / 20s, 1)`, where `age` is measured from `ChainBlockInfo.receivedAt`; empty unless `.connected` |
| centre dot | connection state, refined by ping | `.connected` → ≤150 ms `.fgPrimary`, ≤400 ms `.bgStatusWarning`, else `.bgStatusError`, `.fgTertiary` until the first probe lands; `.connecting` → `.fgTertiary` pulsing; `.offline` → `.bgStatusError` |

**The arc is never coloured** — arc and track are `.fgPrimary` (the track at 0.2 opacity) in every state, so the ring is a neutral gauge whose length is the only thing it says and the dot is the only element that can carry a status colour. The pulse for `.connecting` is on the dot alone, so it reads as state rather than as the gauge moving.

**A healthy chain is monochrome.** A connected chain on a fast link draws its dot `.fgPrimary` too, so the whole mark is one colour and **a status colour appears only when something is wrong** — amber for a slow link, red for a slow-to-the-point-of-broken one or an offline chain. Three rings at a glance answer "is anything wrong" before they answer "what".

**One mark, two sizes.** `diameter` is a property (default 16) and stroke and dot derive from it — `diameter / 8` and `diameter * 0.375` — so the two hosts draw the same proportions rather than two tuned sets of constants. The strip takes the default because its 20pt band bounds it; the panel passes 40.

**Two `Text` overloads, only one of which is a trap.** The visible name is `Text(row.title)` — the `StringProtocol` overload, which is not localized and registers nothing. The accessibility label is `Text(verbatim: "\(row.title), \(row.stateTitle)")`, where `verbatim:` is load-bearing: a plain interpolated literal resolves to the `LocalizedStringKey` overload and string extraction adds a `"%@, %@"` entry to the package catalog.

The label lives on the **column**, with `.accessibilityElement(children: .ignore)` — the ring carries its own label for the nameless strip, and without the ignore VoiceOver would read the chain name twice here.

*Accepted:* "connected but no block seen yet" is separated from "offline" by dot colour alone — both draw an empty ring. In the strip, which has no name, position remains the only cue for which chain is which.

**The arc drains on a view-local tick.** Freshness changes with no new data, so `ChainStatusRingView` wraps its body in `TimelineView(.periodic(from: .now, by: 1))` and computes the fraction against the timeline's date. Pushing a row set every second through `AsyncCurrentValueSubject` → presenter → `UIHostingConfiguration` would reassign the UIKit configuration once a second to express the passage of time. Since the strip is permanent, this 1 Hz redraw is now permanent too — three small shape views, cheap next to the always-on probes and head subscriptions it accompanies. `ChainStatusRingDot` is a separate private view purely to own the pulse animation's `@State` — `ChainStatusRingView` must stay synthesized-`Hashable` for content reuse, which a `@State` property would break.

Row composition lives in `ChainStatusProvider`, not in the module. `ServiceCoordinator.createDefault` builds one `ChainStatusProvider` and one `ChainLatencyProvider` and exposes the former on `ServiceCoordinatorProtocol.chainStatusProvider`; `MainTabBarViewFactory` injects it. One instance, app lifetime. The interactor keeps a single `chainStatusSubscription` forwarding `chainStatusProvider.statusStream()` to `presenter.didReceiveChainStatus(_:)`.

*Rationale:* a per-screen provider would be a visible bug, not just waste. The status registry keys observers by target identity so duplicates do not collapse, and every new instance re-seeds to `.connecting` — rows would flicker back to connecting on each navigation.

The provider consumes `networkStatusService.statusStream(for:)` directly, one call per chain against the shared singleton, and maps `NetworkStatus` → `ChainConnectionState` in `ChainConnectionTarget.swift`. `NetworkStatus` never crosses into `PolkadotUI`. Reaching `.connected` is debounced 300 ms (`withDebounce`). `waitingForNetwork` is global rather than per-chain, so a dropped device path takes all three rows offline together.

**Names are fixed labels, not registry names.** `ChainConnectionTarget.title` returns `Individuality` / `Bulletin` / `Asset Hub`. The registry's own names are long and vary by build arm — the chat target resolves to a People chain, so the registry would render "Paseo People" in nightly and "Polkadot People" in release — which reads badly as a caption under a 40pt ring. Not localized, as chain names never were.

*This deleted a mechanism that used to be load-bearing.* The provider previously took a `ChainRegistryProtocol` purely to resolve names, and subscribed via `chainsSubscribe` because the status stream applies `removeDuplicates()`: a chain reaching `.connected` before the registry loaded would emit exactly once and keep its fallback title forever. Fixed labels make that race unreachable, so `chainsSubscribe`, `handleChainDataUpdate`, the `names` dictionary, the `chainsUnsubscribe(self)` in `deinit` and the registry dependency itself are all gone — `ChainStatusProvider` no longer touches `ChainRegistry` at all. Restoring registry names means restoring that subscription with it.

Seeding is structural, not a step: `rowsSubject` is an `AsyncCurrentValueSubject` **constructed** holding a complete row set, so the first render carries three rows and the trailing button exists from launch, and no later edit can drop a seed-then-push call.

The provider emits `[ChainConnectionStatusViewModel]`, not a hosted configuration. `MainTabBarPresenter.didReceiveChainStatus` wraps them in `SwiftUIContentConfiguration(view: ChainConnectionStatusView(rows:))` at its own push site — a future non-`UIContentView` host (a nav-bar dropdown) would otherwise have to unwrap a configuration it never wanted. Each update pushes a **fresh** configuration; a shared observable view model would mutate without calling `setTrailingPanel`, leaving the glass container's measured panel height stale.

**Latency.** `ChainLatencyProvider` is a *sibling* of the status provider, not a part of it — it owns probe timing only, and `ChainStatusProvider` combines its stream in, so row composition stays in one place.

- Probe is a timed `RPCMethod.healthCheck` (`system_health`) over `chainRegistry.getConnection(for:)`, every 30 s for the app's lifetime, all three chains concurrently in a task group.
- `JSONRPCOptions(resendOnReconnect: false)` is required. The default `true` queues a probe issued while the socket is down and resolves it after reconnect, so the measured interval swallows the whole outage and reports a false multi-second latency. `WebSocketEngine.sendSubstratePing` in the SDK uses the identical option for its own health check.
- Also bounded by `withTimeout(10 s)`: the flag covers a known-down socket, the timeout covers a socket that is up with a node that never answers.
- Reported value is the median of the last 3 samples, so one slow probe cannot move the row.
- Samples are cleared when a chain leaves `.connected`, in `ChainStatusProvider.handleStatusUpdate` — the only place that knows both facts. Without it a drop-and-reconnect shows the pre-drop number for up to 30 s.

`ChainConnectionStatusViewModel.latency` is a raw `Duration?`, not a formatted string. The ring has to *compare* a latency against a threshold, which a localized string cannot do — so the app-side formatters and their two catalog keys were deleted when the text rows were. `Duration` and `Date` are stdlib/Foundation, so `PolkadotUI` still holds no app types, and the bucket thresholds live beside the ring because deciding what a number *means* is presentation, not composition.

*Accepted:* the 20 s freshness window is shorter than the 30 s probe interval, so a ring can drain and refill between two latency samples.

## SPA Hosting

`MainTabBarViewController` conforms to `SPAHosting` (`openProduct(page:)`, `minimizeSPA()`, `closeSPA(tabId:)`). Every entry point routes there through `UIApplication.shared.mainTabBarController` — `ModuleNavigator.openProduct`, `ProductsNavigationRouter.navigateTo`, and `SPAWireframe`. **SPAs are no longer pushed onto the Browse stack or presented full-screen**; the old push/present/dedupe logic in `ModuleNavigator` and `SPAWireframe.showProductSPA` is gone.

Flow of one open:

1. `SPABrowserCoordinator.findOrCreateTab(for:)` matches on `dotDomain`; an existing tab with a different `page` is navigated in place rather than duplicated.
2. `SPAControllerPool` vends (and caches) one `SPAViewController` per tab id, all sharing a single lazily created `SPAFlowState`.
3. `container.mountSPA(_:for:)` sets `selection = .spa(id)` and cross-fades it in.
4. `chromeController.apply(.spa(controller))` — `TabBarChromeContext.spa` marks it `isTabRoot: false, foldDerived: .folded`. **Under `FEATURE_PRODUCTS`, an SPA behaves like a pushed screen: the bar folds and contributes no clearance.** Under `!FEATURE_PRODUCTS` this resolves to `.hidden` rather than folded; the path is unreachable there anyway, since `openProduct` routes to `presentProduct` (a modal `.pageSheet`) instead of `mountSPA`, as the `#if !FEATURE_PRODUCTS` block in `MainTabBarViewController` describes.

`TabBarContainer.select(index:)` re-mounts even when the index is unchanged if the current selection is an SPA, and reselection of the already-selected tab index is treated as a real switch in that case (`handleSelection`). `minimizeSPA()` returns to `currentIndex`; `closeSPA` drops the pooled controller and the stored tab, then minimizes only if that tab was the mounted one.

Chip state flows the VIPER way: `MainTabBarInteractor` observes `SPATabManaging` (`sendOnSubscription: true`), the presenter maps tabs through `SPATabChipViewModelFactory` (name from `ProductHost`, icon from the `.dot` domain via `DotNsResolver`), and the view converts to `DSTabBarChip`. `applyChips()` re-sends on every mount/unmount so `selected` tracks `mountedSPATabId`.

## Adding a Tab

Add a case to `TabBarItem` (`polkadot-app/Modules/MainTabBar/MainTabBarProtocols.swift`) with a localized `title` and an asset, build the controller in `TabFactory.view(for:)`, and add an `AccessibilityID.Tab` entry. `DSTabBarView` lays items out from `DSTabBarRow`; nothing is hardcoded per tab count.

**Tab count affects all unit widths.** `unitWidth` scales with `unitCount`, so adding a tab narrows every item, the centre slot (if expanded), and the trailing slot (if present). `centreIndex` is `itemCount / 2`, so adding a tab moves the centre slot onto whichever item lands in the middle. The centre slot's QR half assumes `.scan` is there; reordering `MainTabBarPresenter.tabItems` moves the slot away from it.
