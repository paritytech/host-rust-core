---
"@parity/truapi": minor
---

Share the container's web API permission checks between CLI scripts and the development bootstrap tag. Scripts remain in Bun with filesystem, environment, subprocess and import access. Dev keeps its existing app URL, assets and hot reload. Public SDK calls and permission checks share one product execution.
