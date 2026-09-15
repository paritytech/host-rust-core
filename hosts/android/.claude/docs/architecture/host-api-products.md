# Products / HostApi / ChatExtension — Three-Tier Environment

Three distinct concepts. Don't conflate.

## Rules at a glance

1. **`blocking`** — A new host call added without a referenced RFC stating its permission model. If no RFC or RFC silent on permissions, escalate to the user; don't invent a policy.
2. **`blocking`** — `ProductId` constructed from arbitrary strings. Always `ProductId.fromUrl(uri)` / `fromLocalId(...)`.
3. **`blocking`** — WebView ownership ambiguity: two classes both call `destroy()` on the same WebView. Single owner.
4. **`major`** — Container script loading split inconsistently across environments. Use `ContainerInjectionStrategy` uniformly.
5. **`major`** — Handler group reaching for a global "current product" instead of an injected `CallingProductIdProvider`.
6. **`major`** — `NavigationPolicy` branching on URL string inside the policy. Classification is external (`DotNsUtils.classifyNavigation`).
7. **`major`** — Multi-room product implemented as multiple `ChatExtension`s instead of a single `ProductChatExtension` (see `chat-extension.md`).
8. **`major`** — Factory-of-factory-of-factory chain — collapse to single `Factory.create(scope, config)`.
9. **`minor`** — Inlining "derive product id from URL" at a call site when the `CallingProductIdProvider` abstraction is already in scope.



| | **Product** | **HostApi** | **ChatExtension** |
|---|---|---|---|
| What it is | A web-based mini-app | The JS↔Kotlin bridge (set of host calls) | A native chat plug-in |
| Where it lives | Loaded into a WebView from `.dot` script | `feature/products/impl/.../hostApi/` | `feature/chats/api` + per-feature impls |
| Identified by | `ProductId` (from `.dot` domain) | n/a — the bridge serves whoever's connected | `ChatExtensionId` |
| Lifecycle | Per-WebView session | Per `HostApiSession` (scoped to a WebView lifetime) | Hilt singleton |
| Composition | Selected by navigation; loaded from DotNs | `HostCallHandlerGroup`s assembled in `HostApiEnvironment` | `@IntoSet` Dagger multibinding |

A product can *integrate* with chat (see `chat-extension.md § Products and chat`). That integration produces a `ProductChatExtension` — a single `ChatExtension` that hosts the product's JS in a hidden WebView and forwards `ChatHostCalls`.

---

## Products

### What is a Product

`feature/products/api/.../model/Product.kt`:

```kotlin
data class Product(
    val id: ProductId,
    val name: String,
    val scriptUrl: String,    // legacy, debug menu only
    val contentHash: String?, // hash of DotNs content
) : Identifiable
```

`ProductId` is a value class derived from the `.dot` domain (`feature/products/api/.../model/ProductId.kt`). Construction is restricted: `ProductId.fromUrl(uri)` or `ProductId.fromLocalId(id)`. Anything that wants to "use the current URL as a ProductId" is wrong.

### Product environments

Three environments where products run:

| Env | Where | Rendering | Navigation |
|---|---|---|---|
| **SPA Browser** | Full-screen WebView | Visible | Inline (same .dot and cross-.dot stays in WebView) |
| **Explore** | Catalog → product list | Visible | Same .dot in WebView; cross-.dot opens a new SPA browser |
| **Chat** | Hidden WebView under a `ProductChatExtension` | Invisible | Disabled (rejects all navigation) |

Each environment composes a different `HostApiEnvironment`.

### ProductRepository / installation

Products are stored in the Room DB and resolved via `ProductRepository`. Scripts are seeded through DotNs and cached with their content hash.

> **Workers load by URL, never as an inlined string.** A worker's entry module can use relative imports against sibling files in the same archive, which only resolve when the script has an origin. Loading it as a blob/`evaluate`-style string silently breaks multi-file workers. The injection must be a `<script type="module" src="…">` pointing at a real served URL.

---

## HostApi

The JS↔Kotlin bridge. Products call JS methods that route through to Kotlin handlers.

### `ContainerBridge`

`feature/products/impl/.../jsEngine/ContainerBridge.kt`:

Generic request/response + subscription handler registry. Message format:
```json
{ "type": "request" | "subscribe" | "unsubscribe", "id": "...", "method": "...", "params": {...} }
```

`bridge.registerHandler<P, R>(method) { params -> ... }` for request/response.
`bridge.registerSubscription<P, E>(method) { params, emit -> ... }` for streams.

### `HostApiSession`

Orchestrates runtime + bridge + handlers for one product instance, scoped to a `CoroutineScope`. Auto-disposes when scope cancels.

### `HostApiEnvironment` — composition

```kotlin
class HostApiEnvironment(
    val navigationPolicy: NavigationPolicy,
    val injectionStrategy: ContainerInjectionStrategy,
    val handlerGroups: List<HostCallHandlerGroup>,
)
```

Three orthogonal axes (navigation, injection, handlers), composed per environment.

### `HostCallHandlerGroup` — the modular handler unit

```kotlin
interface HostCallHandlerGroup {
    fun registerOn(bridge: ContainerBridge)
}
```

Handler groups in code (today):

**Shared across all environments**: `AccountHostCalls`, `ChainHostCalls`, `SigningHostCalls`, `NavigationHostCalls`, `PaymentHostCalls`, `PermissionHostCalls`, `StatementHostCalls`, `PreimageHostCalls`, `AllowanceHostCalls`, `EntropyHostCalls`, `NotificationHostCalls`, `UserIdHostCalls`, `StorageHostCalls`.

**Chat-only**: `ChatHostCalls`.

`HostCallGroupFactory.createShared(...)` builds the shared list; `createChatGroup(...)` adds chat-specific calls.

### Adding a new host call — **always RFC-first**

A new host call is a public protocol surface. New host calls **require an RFC** in `paritytech/host-rust-core` that states:
- Method name, params, response.
- **Permission model** — what permission this call requires (if any), how the user grants it, scoping per product.
- Caching / subscription semantics.

If an RFC doesn't exist or doesn't address the permission model: **stop and ask the user**. Do not invent a permission policy on the fly.

Implementation pattern (post-RFC):

```kotlin
class FooHostCalls(
    private val botApi: ProductsBotApi,
    private val callingProductIdProvider: CallingProductIdProvider,
) : HostCallHandlerGroup {
    override fun registerOn(bridge: ContainerBridge) {
        bridge.registerHandler<FooParams, FooResult>("foo") { params ->
            botApi.foo(callingProductIdProvider.callingProductId(), params)
        }
    }
}
```

Then register in `HostCallGroupFactory.createShared` (or `createChatGroup` if chat-only) and add the matching method to `ProductsBotApi`.

### `CallingProductIdProvider`

Each handler group needs to know **which product** made the call.

- **Chat**: `FixedProductId(productId)` — constant for the extension's lifetime.
- **SPA / Explore**: `UrlDerivedProductId { webView.url }` — extracted from current WebView URL.

Always inject the provider; never let the handler reach into a global "current product".

### Permission gating

`PermissionHostCalls` is the centralized permission gate. Sensitive calls (signing, payments, account access, push) route through it. The exact list of "sensitive" categories is whatever the RFC for each call declares.

---

## JsRuntime — abstraction over the JS engine

`feature/products/impl/.../jsRuntime/JsRuntime.kt`:

```kotlin
interface JsRuntime {
    suspend fun initialize()
    suspend fun loadInitialPage(content: PageContent)
    fun evaluate(script: String)
    fun evaluateAsModule(script: String)
    suspend fun waitForReady(): JsRuntime  // returns self once ready
    // ...
}
```

Today there's `WebViewRuntime` (Android WebView). Future work may add a QuickJS-backed runtime. **Code consuming a `JsRuntime` must not assume WebView semantics.**

### `ContainerInjectionStrategy`

Two strategies based on environment:

| Strategy | Used by | Behavior |
|---|---|---|
| `ExplicitInjection` | Chat | Load empty page → wait ready → eval bridge + container scripts once. |
| `PageLoadInjection` | SPA / Explore | Hook `onPageStarted` → inject bridge + container scripts on every page load (refresh-safe). |

### WebView ownership

**One owner per WebView.** The engine that holds the runtime owns the WebView's lifecycle. UI may *display* the WebView, but it must not also call `destroy()`. Hold WebView ownership in `WebViewRuntime`; UI subscribes to a read-only `StateFlow<WebView?>` if it needs to render.

---

## NavigationPolicy — strategy per environment

`feature/products/impl/.../hostApi/navigation/NavigationPolicy.kt`:

```kotlin
sealed interface NavigationPolicy {
    fun handleNavigation(type: DotNsNavigationType, destination: Uri): NavigationResult

    object Disabled : NavigationPolicy  // Chat: reject all navigation
    class InlineNavigation(val webViewLoader: (String) -> Unit) : NavigationPolicy  // SPA
    class CatalogNavigation(val onProductSelected: (ProductId) -> Unit) : NavigationPolicy  // Explore
}
```

Classification is external (`DotNsUtils.classifyNavigation`); the policy only dispatches. Never branch on URL inside the policy — use the classified type.

---

## Per-product storage isolation

`StorageHostCalls` provides a per-product key-value store. The bridge namespaces keys by `ProductId` so two products cannot read each other's storage. Don't bypass this — always use the typed store.

---

## Where new things live

| Concept | Goes in |
|---|---|
| New host call handler group | `feature/products/impl/.../hostApi/handlers/<Name>HostCalls.kt` |
| New `ProductsBotApi` method | `feature/products/impl/.../bot/ProductsBotApi.kt` + impl in `ProductsBotApiImpl` |
| New `NavigationPolicy` variant | `feature/products/impl/.../hostApi/navigation/NavigationPolicy.kt` |
| New `HostApiEnvironment` for a new product runtime mode | the consuming feature (e.g. SPA Browser VM, Explore VM, ChatExtension) — keep the env construction close to the user-facing entry point |

---

## North star

- **RFC-0020 `host_create_transaction`** — the canonical extrinsic-creation host call. New transaction-shaped host calls compose with it rather than duplicating signing/origin logic.
- **RFC-first host calls** — every new host call carries a referenced RFC stating its permission model before implementation. The `host-api-products.md § Adding a new host call` rule is the gate (already `blocking` in the Rules at a glance).
- **Composable `HostApiEnvironment`** — the three axes (`navigationPolicy`, `injectionStrategy`, `handlerGroups`) are orthogonal and remain so. New product modes pick a triple; don't introduce a fourth axis without a design discussion.
- **One owner per WebView** — `WebViewRuntime` owns the lifecycle. Treat any drift back toward UI-managed WebView destruction as a regression.
- **Per-product storage isolation** — never bypass `StorageHostCalls` namespacing. Products cannot read each other's storage by design.

Probe questions on every host-API PR (named-but-not-blocking):
- Does this proposal introduce a new orthogonal axis to `HostApiEnvironment`, or compose within the existing three?
- Does this host call have an RFC + documented permission model?
- Does this WebView interaction respect single ownership?

A "yes" on the first or "no" on the second/third must be named in the architect plan.

## Anti-patterns flagged by past PRs

- Factory soup — `SpaProductWebViewProvider` had a factory-of-factory-of-factory chain. Default to single `Factory.create(scope, config)` returning the working instance.
- WebView ownership ambiguity — engine *and* UI both reaching `destroy()`. Single owner.
- `ProductId` constructed from arbitrary strings — restrict construction via `ProductId.fromUrl(uri)` / `ProductId.fromLocalId(...)`.
- Container script loading inconsistent across environments — unify via `ContainerInjectionStrategy`; don't have different layers in different envs.
- Reaching into product-specific knowledge from `SessionManager` / generic services — generic services expose generic subscription APIs; specific knowledge lives at the calling site.
- Adding new host calls without an RFC (per user direction) — **always require an RFC** that defines the permission model.
