---
"@parity/truapi": patch
---

`truapi-host` writes mnemonics to its plaintext account store only for network presets
whose identities are disposable. On any other preset it signs only with `--mnemonic` or
`HOST_CLI_SIGNER_MNEMONIC`, and refuses auto accounts, stored accounts and mnemonic imports.
Both shipped presets are test networks, so their behaviour is unchanged.
