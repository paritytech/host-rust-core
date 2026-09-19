---
"@parity/truapi": minor
"@parity/truapi-host": minor
---

- Host `device_permission` and `remote_permission` callbacks return `PermissionDecision` (`AllowOnce`, `AllowAlways`, or `Deny`). Native callbacks leave grant storage and consumption to Rust. Embedders must update their callbacks; product-facing responses remain boolean.
- Keep one-use grants in memory. Internal `authorize_remote_permission` and `authorize_device_permission` methods consume them using the public request types, without exposing the methods in the public SDK or API documentation.
- Normalize remote domains, match legacy wildcard coverage, and keep a shared blessed-domain list.
- Require `OpenUrl` for external navigation, including allowed application schemes. A lasting grant covers all external destinations; domain permissions govern outbound network requests.
- Require `Notifications` before `send_push_notification`, prompting when undecided and rejecting delivery when denied.
- Present per-action confirmations without misleading persistent-permission choices.
