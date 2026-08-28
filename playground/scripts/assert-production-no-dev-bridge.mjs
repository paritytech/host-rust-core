import { readdir, readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const bridgeUrl = "http://127.0.0.1:9955/bootstrap.js";
const outputDir = resolve(dirname(fileURLToPath(import.meta.url)), "../out");

async function filesUnder(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = await Promise.all(
    entries.map((entry) => {
      const path = resolve(directory, entry.name);
      return entry.isDirectory() ? filesUnder(path) : [path];
    }),
  );
  return files.flat();
}

const references = [];
for (const path of await filesUnder(outputDir)) {
  if ((await readFile(path)).includes(bridgeUrl)) references.push(path);
}

if (references.length > 0) {
  console.error(
    `Production output contains the development bridge:\n${references.join("\n")}`,
  );
  process.exit(1);
}

console.log("Production output excludes the development bridge");
