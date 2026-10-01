---
"@parity/truapi-host": patch
---

The local signing host caches a product's statement-store allowance key for the current allowance period, so proofs after the first in a period skip the on-chain slot scan. The key is looked up again when the period changes, the local session is cleared or replaced, the product's state is cleared, or the statement store rejects a statement signed with it for having no allowance.
