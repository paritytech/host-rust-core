use clap::ValueEnum;

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
                    "c5af1826b31493f08b7e2a823842f98575b806a784126f28da9608c68665afa5",
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
        required_for_host: false,
    },
    ChainEndpoint {
        genesis: hex_literal_genesis(
            "c5af1826b31493f08b7e2a823842f98575b806a784126f28da9608c68665afa5",
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
    /// Asset Hub genesis hash. Routing metadata only: the chain it connects to is
    /// authoritative for `CheckGenesis`.
    #[allow(dead_code)]
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
}
