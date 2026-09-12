//! Development stand-in for the RFC 0006 payment purse.
//!
//! A real host backs `payment.*` with the user's Coinage wallet, which this
//! headless host does not have. This purse keeps per-purse balances in the
//! signing session's state directory (`dev-purse.json`) so a top-up survives
//! a restart, discloses them without a consent prompt — the CLI auto-approves
//! every confirmation anyway — and credits a top-up without moving anything on
//! chain. Testnet development only: the balance is a number, not money.

use std::collections::BTreeMap;
use std::fs;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use futures::StreamExt;
use futures::stream::BoxStream;
use serde::{Deserialize, Serialize};
use tokio::sync::watch;
use tokio_stream::wrappers::WatchStream;
use truapi::v01;
use truapi_platform::PaymentPurse;

use crate::platform::CliPlatform;

const FILE_NAME: &str = "dev-purse.json";
const MAIN_PURSE: v01::CoinPaymentPurseId = 0;

/// `purse id → balance`, the balance as decimal digits since `u128` is not
/// JSON-safe.
#[derive(Default, Serialize, Deserialize)]
struct DevPurseDocument {
    version: u32,
    purses: BTreeMap<String, String>,
}

type Balances = BTreeMap<v01::CoinPaymentPurseId, v01::Balance>;

pub struct DevPurse {
    /// Resolves the session's state directory at use time, so the file follows
    /// a session switch like the rest of the CLI's persisted state.
    platform: Arc<CliPlatform>,
    balances: Mutex<Balances>,
    changed: watch::Sender<Balances>,
}

impl DevPurse {
    pub fn load(platform: Arc<CliPlatform>) -> Arc<Self> {
        let balances = platform
            .state_dir()
            .map(|dir| dir.join(FILE_NAME))
            .and_then(|path| read_document(&path))
            .unwrap_or_default();
        let (changed, _) = watch::channel(balances.clone());
        Arc::new(Self {
            platform,
            balances: Mutex::new(balances),
            changed,
        })
    }

    fn path(&self) -> Option<PathBuf> {
        self.platform.state_dir().map(|dir| dir.join(FILE_NAME))
    }

    fn credit(&self, purse: v01::CoinPaymentPurseId, amount: v01::Balance) -> Result<(), String> {
        let snapshot = {
            let mut balances = self.balances.lock().expect("dev purse mutex poisoned");
            let balance = balances.entry(purse).or_insert(0);
            *balance = balance
                .checked_add(amount)
                .ok_or_else(|| "purse balance would overflow".to_string())?;
            balances.clone()
        };
        if let Some(path) = self.path() {
            write_document(&path, &snapshot)?;
        }
        self.changed.send_replace(snapshot);
        Ok(())
    }
}

#[async_trait]
impl PaymentPurse for DevPurse {
    fn subscribe_balance(
        &self,
        purse: Option<v01::CoinPaymentPurseId>,
    ) -> BoxStream<'static, v01::Balance> {
        let purse = purse.unwrap_or(MAIN_PURSE);
        let stream = WatchStream::new(self.changed.subscribe())
            .map(move |balances| balances.get(&purse).copied().unwrap_or(0))
            .scan(None, |last, balance| {
                let changed = *last != Some(balance);
                *last = Some(balance);
                futures::future::ready(Some(changed.then_some(balance)))
            })
            .filter_map(futures::future::ready);
        Box::pin(stream)
    }

    async fn top_up(
        &self,
        purse: Option<v01::CoinPaymentPurseId>,
        amount: v01::Balance,
        source: v01::PaymentTopUpSource,
    ) -> Result<(), v01::HostPaymentTopUpError> {
        let v01::PaymentTopUpSource::ProductAccount { derivation_index } = source else {
            // Only the product's own scoped account is a source the headless
            // host can vouch for; a pasted secret key is refused rather than
            // pretended to be spent.
            return Err(v01::HostPaymentTopUpError::InvalidSource);
        };
        if amount == 0 {
            return Err(v01::HostPaymentTopUpError::Unknown {
                reason: "top-up amount must be positive".to_string(),
            });
        }
        let purse = purse.unwrap_or(MAIN_PURSE);
        self.credit(purse, amount)
            .map_err(|reason| v01::HostPaymentTopUpError::Unknown { reason })?;
        tracing::info!(
            purse,
            amount,
            ?derivation_index,
            "dev purse credited (nothing moved on chain)"
        );
        Ok(())
    }
}

fn read_document(path: &PathBuf) -> Option<Balances> {
    let text = fs::read_to_string(path).ok()?;
    let document: DevPurseDocument = serde_json::from_str(&text)
        .map_err(
            |err| tracing::warn!(path = %path.display(), %err, "ignoring unreadable dev purse"),
        )
        .ok()?;
    Some(
        document
            .purses
            .into_iter()
            .filter_map(|(purse, balance)| Some((purse.parse().ok()?, balance.parse().ok()?)))
            .collect(),
    )
}

fn write_document(path: &PathBuf, balances: &Balances) -> Result<(), String> {
    let document = DevPurseDocument {
        version: 1,
        purses: balances
            .iter()
            .map(|(purse, balance)| (purse.to_string(), balance.to_string()))
            .collect(),
    };
    let text = serde_json::to_string_pretty(&document).map_err(|err| err.to_string())?;
    fs::write(path, text).map_err(|err| format!("write {}: {err}", path.display()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn purse() -> Arc<DevPurse> {
        let platform = CliPlatform::new(
            crate::network::Network::Previewnet.config(),
            None,
            crate::platform::ApprovalPolicy::AutoAccept,
            None,
        );
        DevPurse::load(platform)
    }

    #[tokio::test]
    async fn a_subscriber_sees_the_current_balance_then_each_credit() {
        let purse = purse();
        let mut balances = purse.subscribe_balance(None);
        assert_eq!(balances.next().await, Some(0));
        purse
            .top_up(
                None,
                1_000_000,
                v01::PaymentTopUpSource::ProductAccount {
                    derivation_index: v01::DerivationIndex::Index(1),
                },
            )
            .await
            .expect("top-up credits");
        assert_eq!(balances.next().await, Some(1_000_000));
    }

    #[tokio::test]
    async fn purses_are_independent_and_secrets_are_refused() {
        let purse = purse();
        let source = v01::PaymentTopUpSource::ProductAccount {
            derivation_index: v01::DerivationIndex::Index(0),
        };
        purse
            .top_up(Some(7), 5, source)
            .await
            .expect("credits purse 7");
        assert_eq!(purse.subscribe_balance(Some(7)).next().await, Some(5));
        assert_eq!(purse.subscribe_balance(None).next().await, Some(0));
        let refused = purse
            .top_up(
                None,
                5,
                v01::PaymentTopUpSource::PrivateKey {
                    sr25519_secret_key: [0; 64],
                },
            )
            .await;
        assert_eq!(refused, Err(v01::HostPaymentTopUpError::InvalidSource));
    }
}
