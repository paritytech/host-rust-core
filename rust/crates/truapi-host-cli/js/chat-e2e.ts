// End-to-end Chat content screening, run against a host that actually serves
// chat (`truapi-host <role> --execution-kind chat`).
//
// The core screens product-authored message content in the runtime layer,
// above the platform, so a host is never handed content it would have to be
// trusted to screen again. A product-visible error cannot tell that apart from
// a host that was handed the content and refused it, so these cases read the
// host's own transcript (`TRUAPI_CHAT_LOG`, one JSON line per stored message)
// and require it not to have grown.
import { existsSync, readFileSync } from "node:fs";
import type { TrUApiClient } from "../../../../js/packages/truapi/src/index.ts";
import { ChatMessageContent } from "../../../../js/packages/truapi/src/generated/types.ts";
import type {
  ChatMessageContent as ChatMessageContentValue,
  HostChatPostMessageRequest,
} from "../../../../js/packages/truapi/src/generated/types.ts";
import type { DiagnosisRow } from "./diagnosis.ts";

/** Room every case posts into, created by the first case. */
const ROOM_ID = "support";

/** Published limits, mirrored from `truapi-platform` so a case can cross one. */
const BODY_MAX_BYTES = 16 * 1024;

/** Messages the host has stored so far, one JSON object per line. */
function transcript(path: string): string[] {
  if (!existsSync(path)) {
    return [];
  }
  return readFileSync(path, "utf8")
    .split("\n")
    .filter((line) => line.length > 0);
}

/** The payload of the last message the host stored, SCALE-encoded as hex. */
function lastStoredPayload(path: string): string | undefined {
  const lines = transcript(path);
  const last = lines[lines.length - 1];
  return last ? (JSON.parse(last).payload as string) : undefined;
}

function hex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

/** One case: a payload, and whether the host may ever see it. */
interface Case {
  name: string;
  payload: ChatMessageContentValue;
}

/** Payloads the core must refuse before any host is handed them. */
const REFUSED: Case[] = [
  {
    name: "a url the host would fetch or open",
    payload: {
      tag: "File",
      value: {
        url: "javascript:alert(document.cookie)",
        fileName: "receipt.pdf",
        mimeType: "application/pdf",
        sizeBytes: 1n,
      },
    },
  },
  {
    name: "a file name that addresses a path",
    payload: {
      tag: "File",
      value: {
        url: "https://files.invalid/receipt.pdf",
        fileName: "../../etc/passwd",
        mimeType: "application/pdf",
        sizeBytes: 1n,
      },
    },
  },
  {
    name: "a body past the published budget",
    payload: { tag: "Text", value: { text: "a".repeat(BODY_MAX_BYTES + 1) } },
  },
  {
    name: "two action ids that normalize alike",
    payload: {
      tag: "Actions",
      value: {
        text: "Pick one",
        actions: [
          { actionId: "caf\u00e9", title: "Precomposed" },
          // The same identifier written with a combining accent. NFC folds it
          // onto the one above, and a trigger naming that key could not say
          // which button was pressed.
          { actionId: "cafe\u0301", title: "Decomposed" },
        ],
        layout: "Column",
      },
    },
  },
];

/**
 * Create a room, post content a host can render, then require every refused
 * payload to be refused without reaching the host's transcript.
 */
export async function runChatScreeningE2e(
  client: TrUApiClient,
  chatLogPath: string | undefined,
): Promise<DiagnosisRow[]> {
  const rows: DiagnosisRow[] = [];
  const row = (
    methodName: string,
    status: DiagnosisRow["status"],
    output: string,
    startedAt: number,
  ): DiagnosisRow => ({
    id: `Chat/${methodName}`,
    serviceName: "Chat",
    methodName,
    status,
    output,
    durationMs: Math.round(performance.now() - startedAt),
  });

  if (!chatLogPath) {
    return [
      row(
        "content_screening_e2e",
        "skipped",
        "TRUAPI_CHAT_LOG not set; cannot tell a core rejection from a host one",
        performance.now(),
      ),
    ];
  }

  let startedAt = performance.now();
  const created = await client.chat.createRoom({
    roomId: ROOM_ID,
    name: "Support",
    icon: "https://rooms.invalid/support.png",
  });
  rows.push(
    created.isOk()
      ? row("create_room", "pass", String(created.value.status), startedAt)
      : row("create_room", "fail", JSON.stringify(created.error), startedAt),
  );
  if (created.isErr()) {
    return rows;
  }

  // Content a host can render reaches it byte for byte: line breaks and tabs
  // survive, because a body is screened but never trimmed or normalized.
  startedAt = performance.now();
  const text = "line one\nline two\twith a tab";
  const accepted: HostChatPostMessageRequest = {
    roomId: ROOM_ID,
    payload: { tag: "Text", value: { text } },
  };
  const posted = await client.chat.postMessage(accepted);
  if (posted.isErr()) {
    rows.push(
      row("post_message", "fail", JSON.stringify(posted.error), startedAt),
    );
    return rows;
  }
  const storedPayload = lastStoredPayload(chatLogPath);
  const sentPayload = hex(ChatMessageContent.enc(accepted.payload));
  rows.push(
    storedPayload === sentPayload
      ? row(
          "post_message",
          "pass",
          `message ${posted.value.messageId} stored byte for byte`,
          startedAt,
        )
      : row(
          "post_message",
          "fail",
          `host stored ${storedPayload ?? "nothing"}, product sent ${sentPayload}`,
          startedAt,
        ),
  );

  for (const refused of REFUSED) {
    startedAt = performance.now();
    const before = transcript(chatLogPath).length;
    const result = await client.chat.postMessage({
      roomId: ROOM_ID,
      payload: refused.payload,
    });
    const after = transcript(chatLogPath).length;
    const methodName = `post_message_refuses_${refused.name.replace(/\s+/g, "_")}`;
    if (result.isOk()) {
      rows.push(
        row(methodName, "fail", `accepted: ${result.value.messageId}`, startedAt),
      );
      continue;
    }
    rows.push(
      after === before
        ? row(
            methodName,
            "pass",
            `${JSON.stringify(result.error)}; host transcript unchanged`,
            startedAt,
          )
        : row(
            methodName,
            "fail",
            `rejected the product, but the host stored ${after - before} message(s)`,
            startedAt,
          ),
    );
  }

  return rows;
}

/** Non-`skipped` rows that did not pass. */
export function chatScreeningFailures(rows: DiagnosisRow[]): DiagnosisRow[] {
  return rows.filter((entry) => entry.status === "fail");
}
