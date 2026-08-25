import { spawn } from "node:child_process";
import { INSTALL_HELP, resolveHostBinary } from "../binary.js";

/**
 * `truapi-host` passthrough: resolve a binary through the package's chain and
 * exec it with the caller's arguments, so `pnpm exec truapi-host …` behaves
 * exactly like the cargo-installed CLI — but pinned by the lockfile.
 */
export function runHostCli(argv: string[]): void {
  let resolved;
  try {
    resolved = resolveHostBinary();
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  }
  const child = spawn(resolved.command, argv, { stdio: "inherit" });
  child.once("error", (error: NodeJS.ErrnoException) => {
    console.error(
      error.code === "ENOENT"
        ? `no truapi-host binary at ${resolved.command} (from ${resolved.source})\n\n${INSTALL_HELP}`
        : String(error),
    );
    process.exit(1);
  });
  const forward = (signal: NodeJS.Signals) => () => child.kill(signal);
  process.on("SIGINT", forward("SIGINT"));
  process.on("SIGTERM", forward("SIGTERM"));
  child.once("exit", (code) => process.exit(code ?? 0));
}
