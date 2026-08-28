//! Browser bridge served to products during local development.

/// Path the bridge script is served from on the frame endpoint.
pub const PATH: &str = "/bootstrap.js";

/// JavaScript that connects a plain browser tab to this host's frame socket.
///
/// The page ends up with the same `window.__HOST_API_PORT__` a native webview
/// host injects, so the SDK's sandbox bootstrap adopts it without knowing the
/// transport underneath is a loopback WebSocket. Products reference this from
/// a development-only `<script>` tag and need no other host-specific code.
pub fn script(frame_url: &str) -> String {
    let url = serde_json::to_string(frame_url).expect("a string always serializes");
    format!(
        r#"(function () {{
  var url = {url};
  if (window.__HOST_API_PORT__) return;

  var channel = new MessageChannel();
  var socket = new WebSocket(url);
  socket.binaryType = "arraybuffer";
  // Frames the product posts before the socket opens. The SDK queues nothing
  // once it holds a port, so the queue has to live on this side.
  var pending = [];

  channel.port2.onmessage = function (event) {{
    if (socket.readyState === WebSocket.OPEN) socket.send(event.data);
    else pending.push(event.data);
  }};
  channel.port2.start();

  socket.onopen = function () {{
    for (var i = 0; i < pending.length; i++) socket.send(pending[i]);
    pending.length = 0;
  }};
  // The SDK's provider only accepts Uint8Array, never a bare ArrayBuffer.
  socket.onmessage = function (event) {{
    channel.port2.postMessage(new Uint8Array(event.data));
  }};
  // Nothing can be signalled down a MessagePort, so a closed socket looks like
  // an app that has hung. Say so instead.
  socket.onclose = function () {{
    console.warn("[truapi-host] frame socket closed; reload once the host is back");
  }};
  socket.onerror = function () {{
    console.error("[truapi-host] cannot reach " + url + " - is truapi-host running?");
  }};

  window.__HOST_API_PORT__ = channel.port1;
  window.__HOST_WEBVIEW_MARK__ = true;
  window.dispatchEvent(new Event("truapi-native-ready"));
}})();
"#
    )
}

/// HTTP URL the bridge script is served from, for a frame endpoint that has
/// one. A private Unix socket is reachable only by the CLI's own product
/// runner, so it has no browser-facing address.
pub fn bridge_url(frame_url: &str) -> Option<String> {
    let authority = frame_url.strip_prefix("ws://")?;
    Some(format!("http://{authority}{PATH}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bridge_url_is_offered_only_for_tcp_endpoints() {
        assert_eq!(
            bridge_url("ws://127.0.0.1:9955").as_deref(),
            Some("http://127.0.0.1:9955/bootstrap.js")
        );
        assert_eq!(bridge_url("ws+unix:/tmp/truapi/frames.sock"), None);
    }

    #[test]
    fn script_embeds_the_endpoint_as_a_string_literal() {
        let script = script("ws://127.0.0.1:9955");
        assert!(script.contains(r#"var url = "ws://127.0.0.1:9955";"#));
    }

    /// The endpoint reaches this from a command-line flag, so a quote in it
    /// must stay inside the literal rather than closing it and becoming code.
    #[test]
    fn script_escapes_an_endpoint_that_would_otherwise_break_out() {
        let script = script(r#"ws://x";alert(1);//"#);
        let declaration = script
            .lines()
            .find(|line| line.trim_start().starts_with("var url ="))
            .expect("the script declares the endpoint");

        assert_eq!(declaration.trim(), r#"var url = "ws://x\";alert(1);//";"#);
    }
}
