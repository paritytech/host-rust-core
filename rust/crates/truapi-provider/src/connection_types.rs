//! The kinds of peer connection the browser light client opens.

use smoldot_light::platform::ConnectionType;
#[cfg(all(feature = "js", target_arch = "wasm32"))]
use wasm_bindgen::prelude::*;

/// Which kinds of connection the browser light client opens to a peer. All
/// are allowed by default.
#[cfg_attr(all(feature = "js", target_arch = "wasm32"), wasm_bindgen)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ConnectionTypes {
    /// Secure `wss://` WebSocket.
    #[cfg_attr(
        all(feature = "js", target_arch = "wasm32"),
        wasm_bindgen(js_name = secureWebSocket)
    )]
    pub secure_websocket: bool,
    /// Plain `ws://` WebSocket to a localhost peer.
    #[cfg_attr(
        all(feature = "js", target_arch = "wasm32"),
        wasm_bindgen(js_name = localWebSocket)
    )]
    pub local_websocket: bool,
    /// Plain `ws://` WebSocket to any other peer.
    #[cfg_attr(
        all(feature = "js", target_arch = "wasm32"),
        wasm_bindgen(js_name = remoteWebSocket)
    )]
    pub remote_websocket: bool,
}

#[cfg_attr(all(feature = "js", target_arch = "wasm32"), wasm_bindgen)]
impl ConnectionTypes {
    /// Allow every kind of connection.
    #[cfg_attr(all(feature = "js", target_arch = "wasm32"), wasm_bindgen(constructor))]
    pub fn new() -> Self {
        ConnectionTypes {
            secure_websocket: true,
            local_websocket: true,
            remote_websocket: true,
        }
    }
}

impl Default for ConnectionTypes {
    /// Same as [`ConnectionTypes::new`]: every kind allowed.
    fn default() -> Self {
        Self::new()
    }
}

impl ConnectionTypes {
    /// Whether a connection of `connection_type` may be opened.
    pub(crate) fn allows(&self, connection_type: ConnectionType) -> bool {
        match connection_type {
            ConnectionType::WebSocketDns { secure: true, .. } => self.secure_websocket,
            ConnectionType::WebSocketIpv4 {
                remote_is_localhost,
            }
            | ConnectionType::WebSocketIpv6 {
                remote_is_localhost,
            }
            | ConnectionType::WebSocketDns {
                remote_is_localhost,
                ..
            } => {
                if remote_is_localhost {
                    self.local_websocket
                } else {
                    self.remote_websocket
                }
            }
            _ => false,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::ConnectionTypes;
    use smoldot_light::platform::ConnectionType;

    const REMOTE_WS: ConnectionType = ConnectionType::WebSocketIpv6 {
        remote_is_localhost: false,
    };
    const LOCAL_WS: ConnectionType = ConnectionType::WebSocketIpv4 {
        remote_is_localhost: true,
    };
    const WSS: ConnectionType = ConnectionType::WebSocketDns {
        secure: true,
        remote_is_localhost: false,
    };

    #[test]
    fn the_default_allows_every_websocket() {
        let types = ConnectionTypes::default();
        assert!(types.allows(REMOTE_WS) && types.allows(LOCAL_WS) && types.allows(WSS));
        assert!(!types.allows(ConnectionType::TcpIpv4));
    }

    #[test]
    fn remote_plain_websocket_can_be_refused_alone() {
        let types = ConnectionTypes {
            remote_websocket: false,
            ..ConnectionTypes::default()
        };
        assert!(!types.allows(REMOTE_WS));
        assert!(!types.allows(ConnectionType::WebSocketDns {
            secure: false,
            remote_is_localhost: false,
        }));
        assert!(types.allows(LOCAL_WS) && types.allows(WSS));
    }
}
