---
"@parity/truapi-host": patch
---

Every host-called native entry point runs its work on the core runtime, and the host only awaits the result, so no core code runs on a Swift or Kotlin thread and a main-thread caller never blocks. The runtime constructor, `disconnect`, `activate_local_session`, the statement renewal target methods, `renew_statement_allowances`, `set_permission_authorization_status`, `session_chat_identity_key`, `device_encryption_key` and `product_subtree_public_key` are async. This breaks both native host APIs: on Android, `TrUAPIHostRuntime.create` replaces the constructor and these methods are `suspend`; on iOS, `TrUAPIHostRuntime.init` and these methods are `async`. Cancelling the host call cancels the core work, and a panic in it surfaces as before.
