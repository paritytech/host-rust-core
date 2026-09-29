import { describe, expect, test } from "bun:test";
import type { TrUApiClient } from "../../../../js/packages/truapi/src/index.ts";
import { runAutomaticUploadE2e } from "./automatic-upload-e2e.ts";

describe("AutomaticUpload e2e", () => {
  test("skips without touching the client when the transcript is not wired", async () => {
    const row = await runAutomaticUploadE2e(
      undefined as unknown as TrUApiClient,
      undefined,
    );
    expect(row.status).toBe("skipped");
    expect(row.output).toContain("TRUAPI_APPROVALS_LOG");
  });
});
