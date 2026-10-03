---
"@parity/truapi": minor
---

Funding status adds `Converting`. Signing hosts assign an inbound session its deposit account with `assign_funding_deposit` (Rust API), skipping accounts that already hold funds; the core watches it at finalized Asset Hub blocks and reports `Converting` once the expected balance arrives.
