#!/usr/bin/env node
import { runDevHost } from "../dist/bin/dev-host.js";

try {
  await runDevHost(process.argv.slice(2));
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}
