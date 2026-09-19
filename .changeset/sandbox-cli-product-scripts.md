---
"@parity/truapi": minor
---

Change the default execution of CLI product scripts to a sandboxed browser. Scripts using Node modules, `process`, `Bun` or filesystem access must explicitly use `--trusted-script` with `--script`. Sandboxed scripts require Chromium installed through `truapi-host install-browser`.

Authorize fetch, asynchronous XHR and WebSocket operations through Rust, preserving native redirect behavior after the initial authorization. Permission prompts identify the destination and preserve Allow once, Allow always and Deny. Package the shared `js/container` bundle, browser SDK, matching browser driver and script compiler alongside the CLI runner.
