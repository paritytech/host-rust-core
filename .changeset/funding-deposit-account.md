---
"@parity/truapi": patch
---

Signing hosts derive funding accounts under the reserved `fund.<network suffix>` product, labelled as getcash labels them, with a persisted counter per source (Rust API: `funding_account`, `next_funding_account_number`). No product can use accounts under `fund.<network suffix>`.
