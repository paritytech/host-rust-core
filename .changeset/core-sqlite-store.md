---
"@parity/truapi": minor
"@parity/truapi-host": minor
---

Give native signing hosts a core-owned SQLite database. `NativeHostRuntimeConfig.database_directory` (`databaseDirectory` in the Swift and Kotlin wrappers) names an existing, writable directory; the runtime refuses to start when it does not exist, and opens `core.sqlite3` there on first use. `coreDatabaseStatus()` opens it and reports the SQLite version, schema version and path.
