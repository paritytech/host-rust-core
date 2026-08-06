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
    /// Previewnet, the testnet carrying the newer dotNS gateway. Its reservation
    /// signature scheme has `MaxValiditySeconds`.
    #[value(name = "previewnet")]
    Previewnet,
}

/// Env var overriding the identity backend base URL for every command. The URL
/// includes `/api/v1`, for instance a local backend at
/// `http://localhost:8080/api/v1`. Chain endpoints stay on the preset.
pub const IDENTITY_BACKEND_BASE_ENV: &str = "HOST_CLI_IDENTITY_BACKEND_BASE";

impl Network {
    /// Preset resolved with any environment overrides applied.
    pub fn config(self) -> NetworkConfig {
        apply_backend_override(self.preset(), std::env::var(IDENTITY_BACKEND_BASE_ENV).ok())
    }

    /// The unmodified preset values.
    fn preset(self) -> NetworkConfig {
        match self {
            Self::PaseoNextV2 => NetworkConfig {
                id: "paseo-next-v2",
                identity_backend_base: "https://identity-backend-next.parity-testnet.parity.io/api/v1",
                people_ws: PASEO_PEOPLE.ws,
                bulletin_ws: PASEO_BULLETIN.ws,
                asset_hub_ws: PASEO_ASSET_HUB.ws,
                people_genesis: PASEO_PEOPLE.genesis,
                bulletin_genesis: PASEO_BULLETIN.genesis,
                asset_hub_genesis: PASEO_ASSET_HUB.genesis,
                live_chain_endpoints: PASEO_NEXT_V2_CHAIN_ENDPOINTS,
            },
            Self::Previewnet => NetworkConfig {
                id: "previewnet",
                identity_backend_base: "https://polkadot-app-stg.parity.io/api/v1",
                people_ws: PREVIEWNET_PEOPLE.ws,
                // Previewnet has no bulletin chain. Preimage submission keeps
                // using the paseo testnet bulletin.
                bulletin_ws: PASEO_BULLETIN.ws,
                asset_hub_ws: PREVIEWNET_ASSET_HUB.ws,
                people_genesis: PREVIEWNET_PEOPLE.genesis,
                bulletin_genesis: PASEO_BULLETIN.genesis,
                asset_hub_genesis: PREVIEWNET_ASSET_HUB.genesis,
                live_chain_endpoints: PREVIEWNET_CHAIN_ENDPOINTS,
            },
        }
    }
}

/// Replaces the preset's identity backend base with `base` when it carries a
/// non-empty URL. Trailing slashes are stripped so path joins stay clean. The
/// override is leaked once per process, which is fine for a CLI.
fn apply_backend_override(mut config: NetworkConfig, base: Option<String>) -> NetworkConfig {
    if let Some(base) = base {
        let trimmed = base.trim().trim_end_matches('/');
        if !trimmed.is_empty() {
            config.identity_backend_base = Box::leak(trimmed.to_string().into_boxed_str());
        }
    }
    config
}

// Each chain is declared once and reused by both the preset fields and the
// endpoint table. A genesis hash can therefore never drift from the URL it
// routes to. Every route below is host-required: session identity (dotNS
// usernames) resolves through Asset Hub, SSO through People, preimages through
// Bulletin.

const PASEO_ASSET_HUB: ChainEndpoint = ChainEndpoint {
    genesis: hex_literal_genesis(
        "bf0488dbe9daa1de1c08c5f743e26fdc2a4ecd74cf87dd1b4b1eeb99ae4ef19f",
    ),
    ws: "wss://paseo-asset-hub-next-rpc.polkadot.io",
    required_for_host: true,
};

const PASEO_PEOPLE: ChainEndpoint = ChainEndpoint {
    genesis: hex_literal_genesis(
        "c5af1826b31493f08b7e2a823842f98575b806a784126f28da9608c68665afa5",
    ),
    ws: "wss://paseo-people-next-system-rpc.polkadot.io",
    required_for_host: true,
};

const PASEO_BULLETIN: ChainEndpoint = ChainEndpoint {
    genesis: hex_literal_genesis(
        "8cfe6717dc4becfda2e13c488a1e2061ff2dfee96e7d031157f72d36716c0a22",
    ),
    ws: "wss://paseo-bulletin-next-rpc.polkadot.io",
    required_for_host: true,
};

const PREVIEWNET_ASSET_HUB: ChainEndpoint = ChainEndpoint {
    genesis: hex_literal_genesis(
        "4d11c803cc6921429e3876638977ad006ea1bba8cd3976a0bca2f164e7026210",
    ),
    ws: "wss://previewnet.substrate.dev/asset-hub",
    required_for_host: true,
};

const PREVIEWNET_PEOPLE: ChainEndpoint = ChainEndpoint {
    genesis: hex_literal_genesis(
        "3138c6d4ce58c760047a413c2a930e919b4673a841ab4890de59aac3bd037f3d",
    ),
    ws: "wss://previewnet.substrate.dev/people",
    required_for_host: true,
};

const PASEO_NEXT_V2_CHAIN_ENDPOINTS: &[ChainEndpoint] =
    &[PASEO_ASSET_HUB, PASEO_PEOPLE, PASEO_BULLETIN];

const PREVIEWNET_CHAIN_ENDPOINTS: &[ChainEndpoint] =
    &[PREVIEWNET_ASSET_HUB, PREVIEWNET_PEOPLE, PASEO_BULLETIN];

/// Resolved RPC/backend/genesis values for one network preset.
#[derive(Debug, Clone, Copy)]
pub struct NetworkConfig {
    pub id: &'static str,
    pub identity_backend_base: &'static str,
    pub people_ws: &'static str,
    #[allow(dead_code)]
    pub bulletin_ws: &'static str,
    pub asset_hub_ws: &'static str,
    pub people_genesis: [u8; 32],
    pub bulletin_genesis: [u8; 32],
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
            // Reading the raw preset. An exported backend override cannot leak in.
            let config = network.preset();
            let mut routes = vec![
                config.identity_backend_base,
                config.people_ws,
                config.bulletin_ws,
                config.asset_hub_ws,
            ];
            routes.extend(config.live_chain_endpoints.iter().map(|chain| chain.ws));

            for route in routes {
                assert!(
                    ["paseo", "testnet", "previewnet", "-stg."]
                        .iter()
                        .any(|marker| route.contains(marker)),
                    "preset `{}` routes to a host that is not a recognised test \
                     network: {route}",
                    config.id,
                );
            }
        }
    }

    #[test]
    fn backend_override_replaces_only_the_backend_base() {
        let preset = Network::PaseoNextV2.preset();
        let overridden =
            apply_backend_override(preset, Some("http://localhost:8080/api/v1/".to_string()));

        assert_eq!(
            overridden.identity_backend_base, "http://localhost:8080/api/v1",
            "trailing slash is stripped"
        );
        assert_eq!(overridden.asset_hub_ws, preset.asset_hub_ws);
        assert_eq!(
            apply_backend_override(preset, Some("  ".to_string())).identity_backend_base,
            preset.identity_backend_base,
            "a blank override keeps the preset"
        );
    }
}
