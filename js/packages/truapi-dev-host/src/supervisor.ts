import { type ChildProcess, spawn } from "node:child_process";
import { createConnection } from "node:net";
import { INSTALL_HELP, resolveHostBinary } from "./binary.js";

/** The line `--serve` prints once the signer exists and calls are answered. */
const READY_LINE = "Signing host ready";

export interface StartHostOptions {
  /** Loopback port for the frame WebSocket. */
  port: number;
  /** Product id the host serves — it refuses to sign for any other. */
  productId: string;
  /** CLI-native `--network` preset name. */
  network?: string;
  /** Named signer session. Mutually exclusive with `mnemonic`. */
  session?: string;
  /**
   * BIP-39 wallet root to sign as an existing identity instead of the
   * CLI-managed headless one. Travels only as the environment variable the
   * CLI reads natively — never on argv (visible to every process via `ps`)
   * and never into a log line. With `--auto-accept` the connected app can
   * sign anything as this identity: testnet keys only.
   */
  mnemonic?: string;
  /** Binary override; defaults to the package's resolution chain. */
  binary?: string;
  /** Sink for the CLI's own output lines, ANSI-stripped. */
  log?: (line: string) => void;
}

export interface RunningHost {
  /** Frame WebSocket endpoint, `ws://127.0.0.1:<port>`. */
  ws: string;
  /** Stop the host. A no-op for an attached host we did not start. */
  stop: () => void;
  /** True when an already-running host was used instead of spawning one. */
  attached: boolean;
  child?: ChildProcess;
}

export function portIsOpen(port: number): Promise<boolean> {
  return new Promise((done) => {
    const socket = createConnection({ port, host: "127.0.0.1" });
    socket.once("connect", () => (socket.destroy(), done(true)));
    socket.once("error", () => (socket.destroy(), done(false)));
  });
}

/**
 * Spawn a signing host and resolve once it is ready to answer calls.
 *
 * `--serve` is what makes this possible: without it the CLI draws a
 * full-screen transcript and refuses to start without a TTY, which no dev
 * server can give it. `--auto-accept` goes with it, because a process with no
 * terminal cannot prompt for confirmations — which is also why this pairing
 * is strictly for testnets.
 */
export function startHost(options: StartHostOptions): Promise<RunningHost> {
  const { port, productId, network, session, mnemonic, log } = options;
  const resolved = resolveHostBinary(options.binary);
  const args = [
    "signing-host",
    "--serve",
    "--auto-accept",
    "--frame-listen",
    `127.0.0.1:${port}`,
    "--product-id",
    productId,
  ];
  if (network) args.push("--network", network);
  if (session) args.push("--session", session);

  const env = mnemonic
    ? { ...process.env, HOST_CLI_SIGNER_MNEMONIC: mnemonic }
    : process.env;

  const child = spawn(resolved.command, args, {
    stdio: ["ignore", "pipe", "pipe"],
    env,
  });
  const stop = () => void child.kill("SIGTERM");
  const ws = `ws://127.0.0.1:${port}`;

  return new Promise((resolve, reject) => {
    let ready = false;
    let tail = "";
    let announcedFrameEndpoint = false;

    const onLine = (line: string) => {
      // The CLI colours its output; strip so the ready check is on the text.
      const clean = line.replace(/\x1b\[[0-9;]*m/g, "").trim();
      if (!clean) return;
      // `signing-host --serve` prints the frame endpoint after both its
      // "listening" and "serving" lifecycle messages. It is one endpoint, so
      // retain the first occurrence and keep the startup transcript compact.
      if (clean === ws) {
        if (announcedFrameEndpoint) return;
        announcedFrameEndpoint = true;
      }
      tail = `${tail}\n${clean}`.split("\n").slice(-12).join("\n");
      log?.(clean);
      if (!ready && clean.includes(READY_LINE)) {
        ready = true;
        resolve({ ws, stop, child, attached: false });
      }
    };
    const pump = (stream: NodeJS.ReadableStream) => {
      let buffer = "";
      stream.setEncoding("utf8");
      stream.on("data", (chunk: string) => {
        buffer += chunk;
        const lines = buffer.split("\n");
        buffer = lines.pop() ?? "";
        for (const line of lines) onLine(line);
      });
    };
    pump(child.stdout!);
    pump(child.stderr!);

    child.once("error", (error: NodeJS.ErrnoException) => {
      reject(
        error.code === "ENOENT"
          ? new Error(
              `no truapi-host binary at ${resolved.command} (from ${resolved.source})\n\n${INSTALL_HELP}`,
            )
          : error,
      );
    });
    child.once("exit", (code) => {
      if (ready) return;
      reject(
        new Error(
          `truapi-host exited with ${code} before printing "${READY_LINE}".` +
            (tail ? `\n${tail}` : ""),
        ),
      );
    });
  });
}

/**
 * Use the host already on `port` if there is one, otherwise start our own.
 *
 * Attaching matters when you want to watch approvals or type `/session` in
 * the CLI's own window: start it there, and this stays out of the way. The
 * attached host's logs stay in the terminal that started it, and it may serve
 * a different `--product-id` than the app derives — pre-flight it.
 */
export async function ensureHost(
  options: StartHostOptions,
): Promise<RunningHost> {
  const ws = `ws://127.0.0.1:${options.port}`;
  if (await portIsOpen(options.port)) {
    return { ws, stop: () => {}, attached: true };
  }
  return startHost(options);
}
