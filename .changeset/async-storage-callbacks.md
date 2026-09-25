---
"@parity/truapi-host": patch
---

Native host storage and Pocket card removal are asynchronous. The core awaits `core_storage_read`, `core_storage_write`, `core_storage_clear`, `local_storage_read`, `local_storage_write`, `local_storage_clear` and `NativePocketCallbacks::remove_card`, so a host backend that waits on disk, a keystore or a database no longer holds a core thread. On Android, `HostStorage`, `HostCoreStorage` and `PocketHostBridge.removeCard` are `suspend` functions, which is a breaking change for `@parity/android-host` implementers. On iOS the protocols are unchanged, since synchronous implementations satisfy the async requirements. `chain_send` and `chain_close` stay synchronous so requests keep their order, and must only enqueue work.
