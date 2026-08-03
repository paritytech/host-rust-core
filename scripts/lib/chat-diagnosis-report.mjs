/** Decode a SCALE-encoded iOS Chat text message stored in CoreData. */
export function decodeTextMessage(hex) {
  const encoded = Buffer.from(hex, "hex");
  if (encoded[0] !== 0) return undefined;
  const compact = decodeScaleCompact(encoded, 1);
  const start = 1 + compact.bytes;
  return encoded.subarray(start, start + compact.value).toString("utf8");
}

/** Validate a successful Chat report and attach the native host label. */
export function labelChatDiagnosisReport(report, host, expectedSuccesses) {
  const heading = "## Truapi Chat Diagnosis";
  if (
    !report.startsWith(heading) ||
    !report.includes(`**${expectedSuccesses} success · 0 failed**`) ||
    report.includes("❌")
  ) {
    throw new Error(`Chat diagnosis reported a failure:\n${report}`);
  }
  return report.replace(heading, `## Truapi ${host} Chat Diagnosis`);
}

function decodeScaleCompact(encoded, offset) {
  const first = encoded[offset];
  const mode = first & 0b11;
  if (mode === 0) return { value: first >> 2, bytes: 1 };
  if (mode === 1) {
    return { value: encoded.readUInt16LE(offset) >> 2, bytes: 2 };
  }
  if (mode === 2) {
    return { value: encoded.readUInt32LE(offset) >>> 2, bytes: 4 };
  }
  throw new Error(
    "Large SCALE compact values are not expected in Chat reports",
  );
}
