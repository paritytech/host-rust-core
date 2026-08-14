use clap::ValueEnum;
use truapi::latest::ChainIdentifier;
use truapi_platform::{HostChainEntry, HostChainSet};

/// Supported live network presets for the headless hosts.
///
/// Every preset must be a test network. The CLI account store keeps BIP-39
/// mnemonics in plaintext (`accounts.rs`), which is only acceptable for
/// disposable test identities, so adding a production preset means reworking
/// that storage first. The `every_preset_is_a_test_network` test enforces it.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, ValueEnum)]
pub enum Network {
    #[value(name = "paseo-next-v2")]
    #[default]
    PaseoNextV2,
}

impl Network {
    pub fn config(self) -> NetworkConfig {
        match self {
            Self::PaseoNextV2 => NetworkConfig {
                id: "paseo-next-v2",
                identity_backend_base: "https://identity-backend-next.parity-testnet.parity.io/api/v1",
                people_ws: "wss://paseo-people-next-system-rpc.polkadot.io",
                bulletin_ws: "wss://paseo-bulletin-next-rpc.polkadot.io",
                asset_hub_ws: "wss://paseo-asset-hub-next-rpc.polkadot.io",
                people_genesis: hex_literal_genesis(
                    "89a63b11fef2c0273fc72c0d864da0793a665dade5db153e0cab995348c5440f",
                ),
                bulletin_genesis: hex_literal_genesis(
                    "8cfe6717dc4becfda2e13c488a1e2061ff2dfee96e7d031157f72d36716c0a22",
                ),
                asset_hub_genesis: hex_literal_genesis(
                    "23e730eb1c6fecae09c917439a5038cb6122d0d48980e8b9bbf0ff56f94a2ca6",
                ),
                live_chain_endpoints: PASEO_NEXT_V2_CHAIN_ENDPOINTS,
            },
        }
    }
}

const PASEO_NEXT_V2_CHAIN_ENDPOINTS: &[ChainEndpoint] = &[
    ChainEndpoint {
        genesis: hex_literal_genesis(
            "23e730eb1c6fecae09c917439a5038cb6122d0d48980e8b9bbf0ff56f94a2ca6",
        ),
        ws: "wss://paseo-asset-hub-next-rpc.polkadot.io",
        required_for_host: true,
    },
    ChainEndpoint {
        genesis: hex_literal_genesis(
            "89a63b11fef2c0273fc72c0d864da0793a665dade5db153e0cab995348c5440f",
        ),
        ws: "wss://paseo-people-next-system-rpc.polkadot.io",
        required_for_host: true,
    },
    ChainEndpoint {
        genesis: hex_literal_genesis(
            "8cfe6717dc4becfda2e13c488a1e2061ff2dfee96e7d031157f72d36716c0a22",
        ),
        ws: "wss://paseo-bulletin-next-rpc.polkadot.io",
        required_for_host: true,
    },
];

/// Resolved RPC/backend/genesis values for one network preset.
#[derive(Debug, Clone, Copy)]
pub struct NetworkConfig {
    pub id: &'static str,
    pub identity_backend_base: &'static str,
    pub people_ws: &'static str,
    #[allow(dead_code)]
    pub bulletin_ws: &'static str,
    /// Asset Hub RPC, where PGAS allowances are claimed.
    pub asset_hub_ws: &'static str,
    pub people_genesis: [u8; 32],
    pub bulletin_genesis: [u8; 32],
    /// Asset Hub genesis hash, both the role's identity in
    /// [`NetworkConfig::host_chain_set`] and its routing key. The chain it connects
    /// to is authoritative for `CheckGenesis`.
    ///
    /// Wrong here is worse than stale elsewhere: routing matches on it, so a value
    /// the chain does not report sends Asset Hub traffic to the fallback chain.
    pub asset_hub_genesis: [u8; 32],
    pub live_chain_endpoints: &'static [ChainEndpoint],
}

#[derive(Debug, Clone, Copy)]
pub struct ChainEndpoint {
    pub genesis: [u8; 32],
    pub ws: &'static str,
    /// Whether host internals require this route even when optional product
    /// Chain calls are disabled.
    pub required_for_host: bool,
}

impl NetworkConfig {
    /// The chain set this preset serves, for `Features::supported_chains`.
    ///
    /// One entry per role this struct names a genesis hash for. `ChainEndpoint`
    /// carries no role, so `live_chain_endpoints` cannot supply one — an endpoint's
    /// identifier is not recoverable from it, which is why a served role needs its
    /// own field here rather than a lookup into that list.
    ///
    /// Every role listed must also be routable: `WsChainProvider` answers an
    /// unmapped genesis with its fallback URL, so a role the routing filter drops
    /// would connect to the wrong chain while the host claimed to serve it.
    /// `chain::tests::every_served_role_routes_to_its_own_chain` holds that.
    pub fn host_chain_set(&self) -> HostChainSet {
        HostChainSet {
            network: self.id.to_string(),
            chains: vec![
                HostChainEntry {
                    identifier: ChainIdentifier::People,
                    genesis_hash: self.people_genesis,
                },
                HostChainEntry {
                    identifier: ChainIdentifier::Bulletin,
                    genesis_hash: self.bulletin_genesis,
                },
                HostChainEntry {
                    identifier: ChainIdentifier::AssetHub,
                    genesis_hash: self.asset_hub_genesis,
                },
            ],
        }
    }

    /// The preset's own URL for a served role, independent of the genesis-keyed
    /// routing table. Every genesis test resolves the role this way so that a
    /// drifted hash cannot silently move them onto the fallback URL.
    ///
    /// Matched exhaustively on purpose: adding a role to [`ChainIdentifier`]
    /// should stop this compiling rather than reach a `None` that only a test
    /// run notices, and one of those tests is `#[ignore]`d.
    #[cfg(test)]
    pub(crate) fn url_for_role(&self, role: ChainIdentifier) -> Option<&'static str> {
        match role {
            ChainIdentifier::People => Some(self.people_ws),
            ChainIdentifier::Bulletin => Some(self.bulletin_ws),
            ChainIdentifier::AssetHub => Some(self.asset_hub_ws),
            ChainIdentifier::Relay => None,
        }
    }
}

/// Decode a 64-char hex genesis at compile time.
const fn hex_literal_genesis(hex: &str) -> [u8; 32] {
    let bytes = hex.as_bytes();
    let mut out = [0u8; 32];
    let mut i = 0;
    while i < 32 {
        out[i] = hex_nibble(bytes[i * 2]) << 4 | hex_nibble(bytes[i * 2 + 1]);
        i += 1;
    }
    out
}

const fn hex_nibble(c: u8) -> u8 {
    match c {
        b'0'..=b'9' => c - b'0',
        b'a'..=b'f' => c - b'a' + 10,
        _ => panic!("invalid hex digit in genesis literal"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Every served role must match an endpoint that actually routes it, at the
    /// URL the preset names for that role.
    ///
    /// `WsChainProvider::url_for` falls back to `people_ws` for an unrecognised
    /// genesis, so a drifted `people_genesis` still resolves to a working URL
    /// and satisfies every routing assertion. Pinning against
    /// `live_chain_endpoints` checks the constants themselves rather than the
    /// plumbing that reads them.
    ///
    /// This catches the two copies disagreeing, which is what an edit to one of
    /// them causes. It cannot catch both being wrong in the same way; only a
    /// live connection distinguishes that.
    #[test]
    fn served_chain_genesis_hashes_match_the_endpoint_routes() {
        for network in Network::value_variants() {
            let config = network.config();
            for entry in config.host_chain_set().chains {
                let expected_ws = config.url_for_role(entry.identifier).unwrap_or_else(|| {
                    panic!(
                        "{} serves {:?} with no preset URL",
                        config.id, entry.identifier
                    )
                });
                let endpoint = config
                    .live_chain_endpoints
                    .iter()
                    .find(|endpoint| endpoint.genesis == entry.genesis_hash)
                    .unwrap_or_else(|| {
                        panic!(
                            "{} serves {:?} at genesis {} which no endpoint routes",
                            config.id,
                            entry.identifier,
                            hex::encode(entry.genesis_hash)
                        )
                    });
                assert_eq!(
                    endpoint.ws,
                    expected_ws,
                    "{} routes {:?} (genesis {}) to {}, but the preset names {}",
                    config.id,
                    entry.identifier,
                    hex::encode(entry.genesis_hash),
                    endpoint.ws,
                    expected_ws
                );
            }
        }
    }

    /// Anchors the served set itself. Every other test that reads it iterates, so
    /// all of them pass on an empty set; this is what notices a dropped role, and it
    /// covers each preset rather than only the default.
    #[test]
    fn every_preset_serves_exactly_the_expected_roles() {
        for network in Network::value_variants() {
            let config = network.config();
            let served: Vec<ChainIdentifier> = config
                .host_chain_set()
                .chains
                .iter()
                .map(|entry| entry.identifier)
                .collect();

            assert_eq!(
                served,
                vec![
                    ChainIdentifier::People,
                    ChainIdentifier::Bulletin,
                    ChainIdentifier::AssetHub,
                ],
                "{} serves an unexpected role set",
                config.id
            );
        }
    }

    /// Guards the invariant documented on [`Network`]: the plaintext mnemonic
    /// store is only safe for disposable identities, so no preset may point at a
    /// production network. If this fails because a real network was added,
    /// rework the account store rather than relaxing the assertion.
    #[test]
    fn every_preset_is_a_test_network() {
        for network in Network::value_variants() {
            let config = network.config();
            let mut routes = vec![
                config.identity_backend_base,
                config.people_ws,
                config.bulletin_ws,
            ];
            routes.extend(config.live_chain_endpoints.iter().map(|chain| chain.ws));

            for route in routes {
                assert!(
                    route.contains("paseo") || route.contains("testnet"),
                    "preset `{}` routes to a host that is not a recognised test \
                     network: {route}",
                    config.id,
                );
            }
        }
    }

    /// The chains a host advertises must be the chains it reaches.
    ///
    /// [`served_chain_genesis_hashes_match_the_endpoint_routes`] pins the two
    /// constants against each other and cannot see them agreeing on a wrong
    /// value, which is the shape a wiped testnet leaves behind. Only a live
    /// connection distinguishes that, so this asks each endpoint for its own
    /// genesis.
    ///
    /// A drifted hash does not fail loudly on its own: `url_for` answers an
    /// unrecognised genesis with `people_ws`, so every role still resolves to
    /// some working URL, and products read the advertised hash back out of
    /// `get_chain_info` and sign `CheckGenesis` over it.
    ///
    /// Every mismatch is collected before failing, because a wipe drifts more
    /// than one role at a time and an early return would report only the first.
    /// The checked count is asserted at the end: `--ignored` runs this test
    /// *without* [`every_preset_serves_exactly_the_expected_roles`], so nothing
    /// else is holding the served set non-empty in that invocation.
    ///
    /// Ignored by default; needs network access to the preset's chains.
    ///
    /// ```sh
    /// cargo +nightly test -p truapi-host-cli --bin truapi-host \
    ///     advertised_genesis -- --ignored --nocapture
    /// ```
    #[tokio::test]
    #[ignore = "needs network access to the preset's chains"]
    async fn the_advertised_genesis_matches_what_each_chain_reports() {
        use truapi_server::statement_allowance as alloc;

        let mut checked = 0usize;
        let mut drifted = Vec::new();

        for network in Network::value_variants() {
            let config = network.config();
            for entry in config.host_chain_set().chains {
                let ws = config
                    .url_for_role(entry.identifier)
                    .expect("every served role names a preset URL");
                let rpc = alloc::rpc::RpcClient::connect(ws)
                    .await
                    .unwrap_or_else(|err| panic!("connect to {ws}: {err}"));
                let reported = alloc::fetch_genesis_hash(&rpc)
                    .await
                    .unwrap_or_else(|err| panic!("genesis hash from {ws}: {err}"));

                checked += 1;
                if entry.genesis_hash == reported {
                    println!(
                        "{} {:?} {} matches {ws}",
                        config.id,
                        entry.identifier,
                        hex::encode(entry.genesis_hash)
                    );
                } else {
                    drifted.push(format!(
                        "{} advertises {:?} as {} but {ws} reports {}",
                        config.id,
                        entry.identifier,
                        hex::encode(entry.genesis_hash),
                        hex::encode(reported)
                    ));
                }
            }
        }

        assert!(
            drifted.is_empty(),
            "refresh the preset, `well-known-chains.ts` and SPEC.md together:\n{}",
            drifted.join("\n")
        );
        assert_eq!(
            checked,
            Network::value_variants().len() * 3,
            "every preset serves three roles, so anything else means the served \
             set shrank and this test stopped covering it"
        );
    }
}
