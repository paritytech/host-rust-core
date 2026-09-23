---
"@parity/truapi-host": patch
---

A withdrawn request stops on the host, not only at the product. A call cancelled while its confirmation prompt is open stops waiting, and an answer given afterwards authorizes nothing. A withdrawn call never publishes its paired-host request, never sends a broadcast, statement, notification or navigation it had not yet sent, and a broadcast already sent is stopped. Permission prompts still finish and record their answer. Every stop reaches the product as `CallError.Cancelled`.
