import { spawn } from "node:child_process";
import { resolveHostBinary } from "../binary.js";
import { preflightProductAccount, waitForSigner } from "../client.js";
import { resolveNetwork, resolveProductId } from "../networks.js";
import { ensureHost } from "../supervisor.js";

/**
 * One command for "run this app as if it were inside a host".
 *
 *   truapi-dev-host [--app-port <n>] -- <dev command…>
 *
 * Starts a local `truapi-host signing-host`, waits for a real signer
 * identity, pre-flights the product account, then runs the wrapped dev
 * command with the connection details injected into its environment. With no
 * wrapped command it supervises the host until Ctrl-C.
 *
 * Knobs, all optional, read from the environment:
 *   TRUAPI_HOST_PORT        frame WebSocket port       (default 9955)
 *   TRUAPI_HOST_PRODUCT_ID  product label/id to act as (default localhost:<app port>)
 *   TRUAPI_HOST_NETWORK     nextv2 | preview | a CLI-native preset (default nextv2)
 *   TRUAPI_HOST_SESSION     signer session name        (default the CLI's)
 *   TRUAPI_HOST_BIN         path to a locally built CLI binary
 *   TRUAPI_HOST_MNEMONIC    BIP-39 wallet root — sign as YOUR identity instead
 *                           of the auto-managed headless one. --auto-accept
 *                           means the app can sign anything as that identity:
 *                           testnet keys only.
 *
 * The wrapped command receives, each also as a NEXT_PUBLIC_- and
 * VITE_-prefixed copy so frameworks expose them to the browser bundle:
 *   TRUAPI_HOST_WS            frame endpoint (ws://127.0.0.1:<port>)
 *   TRUAPI_HOST_GENESIS_HASH  the network's genesis hash
 *   TRUAPI_HOST_PRODUCT_ID    the resolved product id (only on explicit
 *                             override — a localhost default is what the app
 *                             derives from its own URL anyway)
 *
 * The network and product-id knobs steer BOTH sides — the host gets
 * `--network`/`--product-id`, the app gets the matching injected values — so
 * they cannot disagree. The host refuses to sign for any product id other
 * than the one it serves, so agreement is not cosmetic.
 */
export async function runDevHost(argv: string[]): Promise<void> {
  const separator = argv.indexOf("--");
  const own = separator === -1 ? argv : argv.slice(0, separator);
  const command = separator === -1 ? [] : argv.slice(separator + 1);

  let appPort = 3000;
  for (let i = 0; i < own.length; i++) {
    if (own[i] === "--app-port" && own[i + 1]) {
      appPort = Number(own[++i]);
    } else {
      console.error(
        `unknown argument "${own[i]}" — usage: truapi-dev-host [--app-port <n>] -- <command…>`,
      );
      process.exit(1);
    }
  }

  const log = (message: string) => console.log(`[dev-host] ${message}`);
  const hostLog = (line: string) => console.log(`[host] ${line}`);

  const networkInput = process.env.TRUAPI_HOST_NETWORK;
  const network = resolveNetwork(networkInput);
  if (networkInput && networkInput !== network.name) {
    log(`network "${networkInput}" → CLI preset "${network.name}"`);
  }

  const port = Number(process.env.TRUAPI_HOST_PORT ?? 9955);
  const session = process.env.TRUAPI_HOST_SESSION;
  const mnemonic = process.env.TRUAPI_HOST_MNEMONIC;
  const productIdOverride = process.env.TRUAPI_HOST_PRODUCT_ID;
  const productId = resolveProductId(
    productIdOverride,
    network,
    `localhost:${appPort}`,
  );
  if (productIdOverride && productIdOverride !== productId) {
    log(
      `resolving product label "${productIdOverride}" to "${productId}" for ${network.name}.`,
    );
  }

  // A mnemonic IS the identity — the CLI refuses --session next to it.
  if (mnemonic && session) {
    log(
      `TRUAPI_HOST_SESSION="${session}" is ignored: a mnemonic carries its ` +
        "own identity, and the CLI refuses --session alongside it.",
    );
  }

  const binary = resolveHostBinary();
  if (binary.source !== "platform-package") {
    log(`using truapi-host binary ${binary.command} (${binary.source})`);
  }

  const host = await ensureHost({
    port,
    productId,
    network: network.name,
    session: mnemonic ? undefined : session,
    mnemonic,
    binary: binary.command,
    log: hostLog,
  });
  if (host.attached) {
    log(
      `attaching to the host already on ${host.ws} — its logs stay in the ` +
        `terminal that started it, and it may serve a different --product-id ` +
        `than this app derives. Stop it first to let this command own both.`,
    );
    if (mnemonic) {
      log(
        "TRUAPI_HOST_MNEMONIC is set but an already-running host was " +
          "attached — it keeps whatever identity it started with. Stop it " +
          "to sign as yours.",
      );
    }
  }

  const username = await waitForSigner(host.ws, log);
  log(`signer ready: ${username}`);
  const productReady = await preflightProductAccount(host.ws, productId, {
    verifySigning: host.attached,
    log,
  });
  if (!productReady) {
    host.stop();
    process.exit(1);
  }

  const shutdown = () => host.stop();
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);

  if (command.length === 0) {
    log(`host ready on ${host.ws} — Ctrl-C to stop`);
    return;
  }

  const injected: Record<string, string> = {
    TRUAPI_HOST_WS: host.ws,
    TRUAPI_HOST_GENESIS_HASH: network.genesisHash,
    ...(productIdOverride ? { TRUAPI_HOST_PRODUCT_ID: productId } : {}),
  };
  for (const [key, value] of Object.entries({ ...injected })) {
    injected[`NEXT_PUBLIC_${key}`] = value;
    injected[`VITE_${key}`] = value;
  }

  const child = spawn(command[0], command.slice(1), {
    stdio: "inherit",
    env: { ...process.env, ...injected },
  });
  child.once("exit", (code) => {
    shutdown();
    process.exit(code ?? 0);
  });
}
