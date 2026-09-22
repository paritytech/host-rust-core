import { installContainer } from "../../../../js/container/src/container.ts";
import {
  createTransport,
  createWebSocketProvider,
  decodeWireMessage,
  encodeWireMessage,
} from "../../../../js/packages/truapi/src/index.ts";
import { createCliAuthorization } from "./permissions.ts";

const runtime = window as Window & {
  __HOST_API_PORT__?: MessagePort;
  __HOST_WEBVIEW_MARK__?: boolean;
  __truapi_localhost?: { url: string };
};
if (typeof runtime.__truapi_localhost?.url !== "string")
  throw new Error("CLI frame endpoint is missing");

const channel = new MessageChannel();
const provider = createWebSocketProvider(runtime.__truapi_localhost.url);
const prefix = "cli-permission:";
let closed = false;

const transport = createTransport({
  ...provider,
  postMessage(bytes) {
    const message = decodeWireMessage(bytes)._unsafeUnwrap();
    provider.postMessage(
      encodeWireMessage({
        ...message,
        requestId: prefix + message.requestId,
      })._unsafeUnwrap(),
    );
  },
  subscribe(receive) {
    return provider.subscribe((bytes) => {
      if (closed) return;
      try {
        const message = decodeWireMessage(bytes)._unsafeUnwrap();
        if (message.requestId.startsWith(prefix)) {
          receive(
            encodeWireMessage({
              ...message,
              requestId: message.requestId.slice(prefix.length),
            })._unsafeUnwrap(),
          );
        } else channel.port2.postMessage(bytes);
      } catch {
        dispose();
      }
    });
  },
});

function dispose(): void {
  if (closed) return;
  closed = true;
  transport.dispose();
  if (runtime.__HOST_API_PORT__ === channel.port1)
    delete runtime.__HOST_API_PORT__;
  channel.port1.dispatchEvent(new Event("messageerror"));
  channel.port1.close();
  channel.port2.close();
  provider.dispose();
  window.removeEventListener("pagehide", dispose);
}

channel.port2.onmessage = ({ data }) => {
  if (closed) return;
  try {
    provider.postMessage(data);
  } catch {
    dispose();
  }
};
channel.port2.onmessageerror = dispose;
provider.subscribeClose?.(dispose);
window.addEventListener("pagehide", dispose, { once: true });
runtime.__HOST_API_PORT__ = channel.port1;
runtime.__HOST_WEBVIEW_MARK__ = true;
try {
  installContainer(createCliAuthorization(transport));
} catch (error) {
  dispose();
  throw error;
}
