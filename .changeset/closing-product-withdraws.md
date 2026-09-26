---
"@parity/truapi-host": patch
---

Disposing a product runtime withdraws its in-flight calls before dropping them, so a call waiting on a paired host sends it an SSO `Cancel` and the phone's prompt closes. Calls arriving after disposal answer `Cancelled` without running.
