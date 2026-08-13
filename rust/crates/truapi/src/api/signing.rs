//! Unified [`Signing`] trait.

use crate::versioned::signing::{
    HostCreateTransactionError, HostCreateTransactionRequest, HostCreateTransactionResponse,
    HostCreateTransactionWithLegacyAccountError, HostCreateTransactionWithLegacyAccountRequest,
    HostCreateTransactionWithLegacyAccountResponse,
};
use crate::versioned::signing::{
    HostSignPayloadError, HostSignPayloadRequest, HostSignPayloadResponse,
    HostSignPayloadWithLegacyAccountError, HostSignPayloadWithLegacyAccountRequest,
    HostSignPayloadWithLegacyAccountResponse, HostSignRawError, HostSignRawRequest,
    HostSignRawResponse, HostSignRawWithLegacyAccountError, HostSignRawWithLegacyAccountRequest,
    HostSignRawWithLegacyAccountResponse,
};
use crate::wire;
use crate::{CallContext, CallError};

/// Signing operations.
#[crate::async_trait]
pub trait Signing: Send + Sync {
    /// Construct a transaction for a product account.
    ///
    /// Under Extrinsic V5, omitting `VerifyMultiSignature` from `extensions`
    /// lets the host sign with the signer's key. Listing it — as `Disabled`,
    /// with a proof in a later extension — encodes the given bytes verbatim and
    /// returns an unsigned transaction.
    ///
    /// ```ts
    /// const people = await truapi.chain.getChainInfo({ chain: "People" });
    /// assert(people.isOk(), "getChainInfo failed:", people);
    ///
    /// const payload = await buildCreateTransactionPayload({
    ///   signer: {
    ///     dotNsIdentifier: "truapi-playground.dot",
    ///     derivationIndex: { tag: "Index", value: 0 },
    ///   },
    ///   genesisHash: people.value.genesisHash,
    ///   callData: "0x000000",
    /// });
    /// assert(payload.isOk(), "buildCreateTransactionPayload failed:", payload);
    ///
    /// for (const txExtVersion of [0, 5]) {
    ///   const version = txExtVersion === 0 ? "V4" : "V5";
    ///   // V5 leaves VerifyMultiSignature to the host, which signs. V4 keeps
    ///   // it: that body is a plain concatenation, so dropping one shifts the rest.
    ///   const extensions =
    ///     txExtVersion === 5
    ///       ? payload.value.extensions.filter(
    ///           (ext) => ext.id !== "VerifyMultiSignature",
    ///         )
    ///       : payload.value.extensions;
    ///   const result = await truapi.signing.createTransaction({
    ///     ...payload.value,
    ///     extensions,
    ///     txExtVersion,
    ///   });
    ///   assert(result.isOk(), `${version} createTransaction failed:`, result);
    ///   console.log(`${version} transaction created:`, result.value);
    /// }
    /// ```
    #[wire(request_id = 30)]
    async fn create_transaction(
        &self,
        _cx: &CallContext,
        _request: HostCreateTransactionRequest,
    ) -> Result<HostCreateTransactionResponse, CallError<HostCreateTransactionError>> {
        Err(CallError::unavailable())
    }

    /// Construct a transaction for a non-product (legacy) account.
    ///
    /// The V5 `VerifyMultiSignature` rule is the same as
    /// [`Signing::create_transaction`]: omit it and the host signs, list it and
    /// the given bytes are used with no host signature.
    ///
    /// ```ts
    /// const people = await truapi.chain.getChainInfo({ chain: "People" });
    /// assert(people.isOk(), "getChainInfo failed:", people);
    ///
    /// const accountResult = await truapi.account.getAccount({
    ///   productAccountId: {
    ///     dotNsIdentifier: "truapi-playground.dot",
    ///     derivationIndex: { tag: "Index", value: 0 },
    ///   },
    /// });
    /// assert(accountResult.isOk(), "getAccount failed:", accountResult);
    ///
    /// const payload = await buildCreateTransactionPayload({
    ///   signer: {
    ///     dotNsIdentifier: "truapi-playground.dot",
    ///     derivationIndex: { tag: "Index", value: 0 },
    ///   },
    ///   genesisHash: people.value.genesisHash,
    ///   callData: "0x000000",
    /// });
    /// assert(payload.isOk(), "buildCreateTransactionPayload failed:", payload);
    ///
    /// // Host-owned under V5 only: a V4 body is a plain concatenation, so
    /// // dropping a declared extension there shifts every one after it.
    /// const extensions =
    ///   payload.value.txExtVersion === 5
    ///     ? payload.value.extensions.filter(
    ///         (ext) => ext.id !== "VerifyMultiSignature",
    ///       )
    ///     : payload.value.extensions;
    ///
    /// const result = await truapi.signing.createTransactionWithLegacyAccount({
    ///   ...payload.value,
    ///   extensions,
    ///   signer: accountResult.value.account.publicKey,
    /// });
    /// assert(result.isOk(), "createTransactionWithLegacyAccount failed:", result);
    /// console.log("transaction created:", result.value);
    /// ```
    #[wire(request_id = 32)]
    async fn create_transaction_with_legacy_account(
        &self,
        _cx: &CallContext,
        _request: HostCreateTransactionWithLegacyAccountRequest,
    ) -> Result<
        HostCreateTransactionWithLegacyAccountResponse,
        CallError<HostCreateTransactionWithLegacyAccountError>,
    > {
        Err(CallError::unavailable())
    }

    /// Sign raw bytes with a non-product account.
    ///
    /// ```ts
    /// const accountsResult = await truapi.account.getLegacyAccounts();
    /// assert(accountsResult.isOk(), "getLegacyAccounts failed:", accountsResult);
    /// const identityAccount =
    ///   accountsResult.value.accounts.find((account) => account.name === "Identity") ??
    ///   accountsResult.value.accounts[0];
    /// assert(identityAccount, "no legacy accounts available");
    ///
    /// const result = await truapi.signing.signRawWithLegacyAccount({
    ///   signer: identityAccount.publicKey,
    ///   payload: {
    ///     tag: "Bytes",
    ///     value: { bytes: "0x48656c6c6f" },
    ///   },
    /// });
    /// assert(result.isOk(), "signRawWithLegacyAccount failed:", result);
    /// console.log("raw bytes signed:", result.value);
    /// ```
    #[wire(request_id = 34)]
    async fn sign_raw_with_legacy_account(
        &self,
        _cx: &CallContext,
        _request: HostSignRawWithLegacyAccountRequest,
    ) -> Result<HostSignRawWithLegacyAccountResponse, CallError<HostSignRawWithLegacyAccountError>>
    {
        Err(CallError::unavailable())
    }

    /// Sign an extrinsic payload with a non-product account.
    ///
    /// ```ts
    /// const assetHub = await truapi.chain.getChainInfo({ chain: "AssetHub" });
    /// assert(assetHub.isOk(), "getChainInfo failed:", assetHub);
    ///
    /// const accountResult = await truapi.account.getAccount({
    ///   productAccountId: {
    ///     dotNsIdentifier: "truapi-playground.dot",
    ///     derivationIndex: { tag: "Index", value: 0 },
    ///   },
    /// });
    /// assert(accountResult.isOk(), "getAccount failed:", accountResult);
    ///
    /// const result = await truapi.signing.signPayloadWithLegacyAccount({
    ///   signer: accountResult.value.account.publicKey,
    ///   payload: {
    ///     blockHash: "0xd6eec26135305a8ad257a20d003357284c8aa03d0bdb2b357ab0a22371e11ef2",
    ///     blockNumber: "0x00000000",
    ///     era: "0x00",
    ///     genesisHash: assetHub.value.genesisHash,
    ///     method: "0x00003448656c6c6f2c20776f726c6421",
    ///     nonce: "0x00000000",
    ///     signedExtensions: [],
    ///     specVersion: "0x00000000",
    ///     tip: "0x00000000000000000000000000000000",
    ///     transactionVersion: "0x00000000",
    ///     version: 4,
    ///   },
    /// });
    /// assert(result.isOk(), "signPayloadWithLegacyAccount failed:", result);
    /// console.log("payload signed:", result.value);
    /// ```
    #[wire(request_id = 36)]
    async fn sign_payload_with_legacy_account(
        &self,
        _cx: &CallContext,
        _request: HostSignPayloadWithLegacyAccountRequest,
    ) -> Result<
        HostSignPayloadWithLegacyAccountResponse,
        CallError<HostSignPayloadWithLegacyAccountError>,
    > {
        Err(CallError::unavailable())
    }

    /// Sign raw bytes or a message.
    ///
    /// ```ts
    /// const result = await truapi.signing.signRaw({
    ///   account: { dotNsIdentifier: "truapi-playground.dot", derivationIndex: { tag: "Index", value: 0 } },
    ///   payload: {
    ///     tag: "Bytes",
    ///     value: {
    ///       bytes: "0x48656c6c6f2c20776f726c6421",
    ///     },
    ///   },
    /// });
    /// assert(result.isOk(), "signRaw failed:", result);
    /// console.log("raw bytes signed:", result.value);
    /// ```
    #[wire(request_id = 114)]
    async fn sign_raw(
        &self,
        _cx: &CallContext,
        _request: HostSignRawRequest,
    ) -> Result<HostSignRawResponse, CallError<HostSignRawError>> {
        Err(CallError::unavailable())
    }

    /// Sign an extrinsic payload.
    ///
    /// ```ts
    /// const assetHub = await truapi.chain.getChainInfo({ chain: "AssetHub" });
    /// assert(assetHub.isOk(), "getChainInfo failed:", assetHub);
    ///
    /// const result = await truapi.signing.signPayload({
    ///   account: { dotNsIdentifier: "truapi-playground.dot", derivationIndex: { tag: "Index", value: 0 } },
    ///   payload: {
    ///     blockHash: "0xd6eec26135305a8ad257a20d003357284c8aa03d0bdb2b357ab0a22371e11ef2",
    ///     blockNumber: "0x00000000",
    ///     era: "0x00",
    ///     genesisHash: assetHub.value.genesisHash,
    ///     method: "0x00003448656c6c6f2c20776f726c6421",
    ///     nonce: "0x00000000",
    ///     signedExtensions: [],
    ///     specVersion: "0x00000000",
    ///     tip: "0x00000000000000000000000000000000",
    ///     transactionVersion: "0x00000000",
    ///     version: 4,
    ///   },
    /// });
    /// assert(result.isOk(), "signPayload failed:", result);
    /// console.log("payload signed:", result.value);
    /// ```
    #[wire(request_id = 116)]
    async fn sign_payload(
        &self,
        _cx: &CallContext,
        _request: HostSignPayloadRequest,
    ) -> Result<HostSignPayloadResponse, CallError<HostSignPayloadError>> {
        Err(CallError::unavailable())
    }
}
