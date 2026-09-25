---
"@parity/truapi": patch
"@parity/truapi-host": patch
---

Disposing a product runtime withdraws its in-flight calls before dropping them, so a call waiting on a paired host sends it an SSO `Cancel` and the phone's prompt closes. The CLI and native WebSocket hosts let those calls finish instead of aborting them when a connection closes.
