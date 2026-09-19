import { afterEach, expect, test } from "bun:test";
import { mkdtemp, mkdir, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { buildProductScript } from "./sandbox-build.ts";

const directories: string[] = [];

async function fixture(source: string) {
  const directory = await mkdtemp(join(tmpdir(), "truapi-product-build-"));
  directories.push(directory);
  const product = join(directory, "product");
  await mkdir(product);
  const script = join(product, "index.ts");
  await writeFile(script, source);
  return { directory, product, script };
}

afterEach(async () => {
  await Promise.all(
    directories.splice(0).map((path) => rm(path, { recursive: true })),
  );
});

test("prepares TypeScript and local imports without evaluating product code", async () => {
  const { product, script } = await fixture(
    'import { answer } from "./answer.ts"; globalThis.productWasEvaluated = true; export default async () => answer;',
  );
  await writeFile(
    join(product, "answer.ts"),
    "export const answer: number = 42;",
  );
  const source = await buildProductScript(script);
  expect(source).toContain("42");
  expect(Object.hasOwn(globalThis, "productWasEvaluated")).toBe(false);
});

test("rejects imports of host capabilities", async () => {
  const { script } = await fixture(
    'import { readFile } from "node:fs/promises"; console.log(readFile);',
  );
  await expect(buildProductScript(script)).rejects.toThrow(
    /host module|node:fs/,
  );
});

test("does not bundle files outside the product directory", async () => {
  const { directory, script } = await fixture(
    'import secret from "../secret.json"; console.log(secret);',
  );
  await writeFile(join(directory, "secret.json"), '{"secret":"host-only"}');
  await expect(buildProductScript(script)).rejects.toThrow(/outside.*product/);
});

test("symlinks cannot bring host files into the product bundle", async () => {
  const { directory, product, script } = await fixture(
    'import secret from "./secret.json"; console.log(secret);',
  );
  await writeFile(join(directory, "secret.json"), '{"secret":"host-only"}');
  await symlink(join(directory, "secret.json"), join(product, "secret.json"));
  await expect(buildProductScript(script)).rejects.toThrow(/outside.*product/);
});

test("never embeds inherited environment secrets", async () => {
  const { script } = await fixture(
    "console.log(process.env.TRUAPI_BUILD_SECRET);",
  );
  process.env.TRUAPI_BUILD_SECRET = "not-for-the-product-7283";
  try {
    expect(await buildProductScript(script)).not.toContain(
      "not-for-the-product-7283",
    );
  } finally {
    delete process.env.TRUAPI_BUILD_SECRET;
  }
});

test("dependency directory symlinks cannot expand the product input boundary", async () => {
  const { directory, product, script } = await fixture(
    'import secret from "./node_modules/secret.json"; console.log(secret);',
  );
  const privateDirectory = join(directory, "private");
  await mkdir(privateDirectory);
  await writeFile(
    join(privateDirectory, "secret.json"),
    '{"secret":"host-only"}',
  );
  await symlink(privateDirectory, join(product, "node_modules"));
  await expect(buildProductScript(script)).rejects.toThrow(
    /outside.*product|dependency.*symlink/,
  );
});

test("product macros cannot execute with launcher privileges", async () => {
  const { directory, product, script } = await fixture(
    'import { probe } from "./macro.ts" with { type: "macro" }; console.log(probe());',
  );
  const sentinel = join(directory, "macro-executed");
  await writeFile(
    join(product, "macro.ts"),
    `import { writeFileSync } from "node:fs";
     export function probe() {
       writeFileSync(${JSON.stringify(sentinel)}, "macro ran");
       return "macro-ran-with-host-privileges";
     }`,
  );
  await expect(buildProductScript(script)).rejects.toThrow(/macro/i);
  expect(await Bun.file(sentinel).exists()).toBe(false);
});
