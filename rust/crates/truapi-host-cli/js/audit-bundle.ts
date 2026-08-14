import { isBuiltin } from "node:module";

const bundlePath = process.argv[2];
if (!bundlePath) throw new Error("bundle path is required");

const source = await Bun.file(bundlePath).text();
const dynamicImport = /\b(?:import|require)\s*\(/.exec(source);
if (dynamicImport) {
  throw new Error(
    `product bundle retains executable imports: ${dynamicImport[0]}`,
  );
}

const imports = new Bun.Transpiler({ loader: "js" }).scan(source).imports;
const unsafe = imports.filter(({ path }) => !isBuiltin(path));
if (unsafe.length > 0) {
  const detail = unsafe
    .map(({ kind, path }) => `${kind}:${path || "<dynamic>"}`)
    .join(", ");
  throw new Error(`product bundle retains executable imports: ${detail}`);
}
