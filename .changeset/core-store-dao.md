---
"@parity/truapi": patch
"@parity/truapi-host": patch
---

Add `#[dao]` data-access objects over the core SQLite database: SQL-annotated trait methods become `rusqlite` calls that compose inside one write, plus an async twin of each method that takes its own connection.
