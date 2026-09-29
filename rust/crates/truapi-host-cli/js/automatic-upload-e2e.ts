// End-to-end automatic-upload check (RFC 0010): after an approved
// `AutomaticUpload` allocation, `preimage.submit` uploads within the consent's
// limits without consulting the host's confirmation prompt, and an upload over
// the size limit still asks.
//
// Reads the same approvals transcript as the AutoSigning case; see
// `auto-signing-e2e.ts` for how the host CLI writes it.
import { existsSync, readFileSync } from "node:fs";
import type { TrUApiClient } from "../../../../js/packages/truapi/src/index.ts";
import {
  ALLOCATION_APPROVAL_ACTION,
  actionLines,
  approvalLines,
  newLinesSince,
} from "./auto-signing-e2e.ts";
import type { DiagnosisRow } from "./diagnosis.ts";

export const PREIMAGE_APPROVAL_ACTION = "submit preimage";

/** Largest upload the consent covers, mirrored from the core's limit. */
export const AUTOMATIC_UPLOAD_MAX_BYTES = 256 * 1024;

/** A fresh preimage of `size` bytes, so no upload is deduplicated by content. */
function randomPreimage(size: number): `0x${string}` {
  const bytes = new Uint8Array(size);
  for (let offset = 0; offset < size; offset += 65_536) {
    crypto.getRandomValues(bytes.subarray(offset, offset + 65_536));
  }
  return `0x${bytes.toHex()}`;
}

/**
 * Allocate `AutomaticUpload`, require two small uploads to succeed without a
 * preimage prompt, then require an upload over the size limit to prompt.
 * Reported as one extra diagnosis row.
 */
export async function runAutomaticUploadE2e(
  client: TrUApiClient,
  approvalsLogPath: string | undefined,
): Promise<DiagnosisRow> {
  const startedAt = performance.now();
  const finish = (
    status: DiagnosisRow["status"],
    output: string,
  ): DiagnosisRow => ({
    id: "Resource Allocation/automatic_upload_e2e",
    serviceName: "Resource Allocation",
    methodName: "automatic_upload_e2e",
    status,
    output,
    durationMs: Math.round(performance.now() - startedAt),
  });

  if (!approvalsLogPath) {
    return finish(
      "skipped",
      "TRUAPI_APPROVALS_LOG not set; cannot verify prompt-free preimage.submit",
    );
  }
  const readTranscript = () =>
    existsSync(approvalsLogPath)
      ? approvalLines(readFileSync(approvalsLogPath, "utf8"))
      : [];
  /** Upload `size` bytes and return the preimage prompts it consulted. */
  const submit = async (size: number): Promise<string[]> => {
    const before = readTranscript();
    const result = await client.preimage.submit(randomPreimage(size));
    if (!result.isOk()) {
      throw new Error(
        `preimage.submit of ${size} bytes failed: ${JSON.stringify(result.error)}`,
      );
    }
    return actionLines(
      newLinesSince(before, readTranscript()),
      PREIMAGE_APPROVAL_ACTION,
    );
  };

  try {
    const beforeAllocation = readTranscript();
    const allocation = await client.resourceAllocation.request({
      resources: [{ tag: "AutomaticUpload" }],
    });
    if (!allocation.isOk()) {
      return finish(
        "fail",
        `AutomaticUpload allocation failed: ${JSON.stringify(allocation.error)}`,
      );
    }
    const outcome = allocation.value.outcomes[0];
    if (outcome !== "Allocated") {
      return finish("fail", `AutomaticUpload was not allocated: ${outcome}`);
    }
    const allocationWindow = newLinesSince(beforeAllocation, readTranscript());
    if (
      actionLines(allocationWindow, ALLOCATION_APPROVAL_ACTION).length === 0
    ) {
      return finish(
        "fail",
        "approvals transcript recorded no allocation consent; " +
          "prompt tracking is not wired up",
      );
    }

    for (const round of [1, 2]) {
      const prompts = await submit(1024);
      if (prompts.length > 0) {
        return finish(
          "fail",
          `preimage.submit round ${round} consulted a confirmation despite ` +
            `the AutomaticUpload grant: ${prompts.join("; ")}`,
        );
      }
    }
    // Without this the two empty windows above could come from a host that
    // never prompts for preimages at all.
    const oversized = await submit(AUTOMATIC_UPLOAD_MAX_BYTES + 1);
    if (oversized.length === 0) {
      return finish(
        "fail",
        "an upload over the size limit was not confirmed; the consent is " +
          "unbounded or preimage prompts are not tracked",
      );
    }

    return finish(
      "pass",
      "AutomaticUpload allocated with consent; 2 uploads served without a " +
        "confirmation prompt and an oversized upload still prompted",
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return finish("fail", message);
  }
}
