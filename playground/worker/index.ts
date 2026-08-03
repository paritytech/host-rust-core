import { getClientSync } from "@parity/truapi/sandbox";
import { bytesToHex, hexToBytes } from "@parity/truapi/scale";
import type {
  CustomRendererNode,
  HostChatActionSubscribeItem,
  HostChatListSubscribeItem,
  ObservableLike,
  ProductChatCustomMessageRenderChannelItem,
  ProductChatCustomMessageRenderChannelRequest,
} from "@parity/truapi";
import { filter, firstValueFrom, from, Subject, timeout } from "rxjs";
import {
  CHAT_DIAGNOSIS_COPY_ACTION,
  CHAT_DIAGNOSIS_REFRESH_ACTION,
  ChatDiagnosis,
} from "./diagnosis";

const ROOM_ID = "truapi-playground";
const ROOM_NAME = "TrUAPI Playground";
const DIAGNOSIS_COMMAND = "!diagnose";
const ECHO_COMMAND = "!echo";
const RENDER_MESSAGE_TYPE = "truapi-chat-diagnosis";
const runId = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
const diagnosticRoomId = `${ROOM_ID}-diagnosis-${runId}`;
const renderPayload = bytesToHex(
  new TextEncoder().encode(JSON.stringify({ version: 1, runId })),
);

const client = getClientSync();
if (!client) {
  throw new Error("TrUAPI Playground Chat worker requires a host connection");
}
const chat = client.chat;
let customMessageId: string | undefined;
let finalReportPosted = false;
const activeRenderMessageIds = new Set<string>();
const pendingRenderRequests: ProductChatCustomMessageRenderChannelItem[] = [];

const diagnosis = new ChatDiagnosis(() => {
  renderActiveMessages();
  void publishFinalReportIfComplete();
});

const renderRequests =
  new Subject<ProductChatCustomMessageRenderChannelRequest>();
chat.customMessageRenderChannel(renderRequests).subscribe({
  next: handleRenderRequest,
  error(error) {
    diagnosis.fail("Chat/custom_message_render_channel", error);
  },
});

chat.actionSubscribe().subscribe({
  next(action) {
    void handleAction(action).catch((error: unknown) => {
      diagnosis.fail("Chat/action_subscribe", error);
    });
  },
  error(error) {
    diagnosis.fail("Chat/action_subscribe", error);
  },
});

await runStartupDiagnosis().catch((error: unknown) => {
  diagnosis.failPending(error);
  console.error(
    "TrUAPI Playground Chat diagnosis failed",
    error instanceof Error ? error.message : String(error),
  );
});

async function runStartupDiagnosis(): Promise<void> {
  await ensureRoom(ROOM_ID, ROOM_NAME);

  const roomAppeared = waitForRoom(chat.listSubscribe(), diagnosticRoomId);
  const first = await chat.createRoom({
    roomId: diagnosticRoomId,
    name: `TrUAPI Diagnosis ${runId}`,
    icon: "",
  });
  if (first.isErr()) {
    throw new Error(`createRoom failed: ${JSON.stringify(first.error)}`);
  }
  if (first.value.status !== "New") {
    throw new Error(
      `first createRoom returned ${first.value.status}, expected New`,
    );
  }

  const second = await chat.createRoom({
    roomId: diagnosticRoomId,
    name: `TrUAPI Diagnosis ${runId}`,
    icon: "",
  });
  if (second.isErr()) {
    throw new Error(
      `second createRoom failed: ${JSON.stringify(second.error)}`,
    );
  }
  if (second.value.status !== "Exists") {
    throw new Error(
      `second createRoom returned ${second.value.status}, expected Exists`,
    );
  }
  diagnosis.pass("Chat/create_room", "created once, then returned Exists");

  await roomAppeared;
  diagnosis.pass("Chat/list_subscribe", "observed the newly created room");

  const textMessageId = await postMessage({
    tag: "Text",
    value: {
      text: `Chat diagnosis ${runId} started. Send "${DIAGNOSIS_COMMAND}" to test actions.`,
    },
  });
  customMessageId = await postMessage({
    tag: "Custom",
    value: {
      messageType: RENDER_MESSAGE_TYPE,
      payload: renderPayload,
    },
  });
  for (const item of pendingRenderRequests.splice(0)) {
    handleRenderRequest(item);
  }
  if (!textMessageId || !customMessageId || textMessageId === customMessageId) {
    throw new Error("postMessage did not return distinct message identifiers");
  }
  diagnosis.pass("Chat/post_message", "posted text and custom messages");
}

async function ensureRoom(roomId: string, name: string): Promise<void> {
  const result = await chat.createRoom({ roomId, name, icon: "" });
  if (result.isErr()) {
    throw new Error(
      `Unable to create the Playground room: ${JSON.stringify(result.error)}`,
    );
  }
}

function handleRenderRequest(
  item: ProductChatCustomMessageRenderChannelItem,
): void {
  if (item.messageType !== RENDER_MESSAGE_TYPE) {
    rejectRender(item.messageId);
    return;
  }
  try {
    const payload = JSON.parse(
      new TextDecoder().decode(hexToBytes(item.payload)),
    ) as {
      version?: number;
      runId?: string;
    };

    // Native Chat can restore custom messages from an earlier worker run before
    // it asks the current run to render its own message. Those requests belong
    // to renderer state that no longer exists, so reject them without turning
    // the current diagnosis red.
    if (payload.runId !== runId) {
      rejectRender(item.messageId);
      return;
    }
    if (payload.version !== 1) {
      throw new Error("render request did not preserve the custom payload");
    }
    if (!customMessageId) {
      pendingRenderRequests.push(item);
      return;
    }
    if (item.messageId !== customMessageId) {
      throw new Error(
        `render request message ${item.messageId} did not match ${customMessageId}`,
      );
    }

    activeRenderMessageIds.add(item.messageId);
    updateRender(item.messageId, diagnosis.rendererNode());
    diagnosis.pass(
      "Chat/custom_message_render_channel",
      "correlated render work and sent initial and replacement trees",
    );
  } catch (error) {
    diagnosis.fail("Chat/custom_message_render_channel", error);
    rejectRender(item.messageId);
  }
}

function renderActiveMessages(): void {
  const node = diagnosis.rendererNode();
  for (const messageId of activeRenderMessageIds) {
    updateRender(messageId, node);
  }
}

function updateRender(messageId: string, node: CustomRendererNode): void {
  renderRequests.next({ tag: "Update", value: { messageId, node } });
}

function rejectRender(messageId: string): void {
  renderRequests.next({ tag: "Failed", value: { messageId } });
}

async function handleAction(
  action: HostChatActionSubscribeItem,
): Promise<void> {
  if (action.payload.tag === "ActionTriggered") {
    const trigger = action.payload.value;
    if (trigger.messageId === customMessageId) {
      if (trigger.actionId === CHAT_DIAGNOSIS_REFRESH_ACTION) {
        renderActiveMessages();
      } else if (trigger.actionId === CHAT_DIAGNOSIS_COPY_ACTION) {
        await copyDiagnosisReport();
      }
    }
    return;
  }
  if (action.payload.tag !== "MessagePosted") return;
  if (action.payload.value.tag !== "Text") return;

  const text = action.payload.value.value.text.trim();
  if (text === DIAGNOSIS_COMMAND) {
    if (action.roomId !== ROOM_ID) {
      throw new Error(`diagnosis command was delivered for ${action.roomId}`);
    }
    diagnosis.pass(
      "Chat/action_subscribe",
      "received MessagePosted with the originating room",
    );
    return;
  }
  if (!text.startsWith(ECHO_COMMAND)) return;

  const body = text.slice(ECHO_COMMAND.length).trim();
  const result = await chat.postMessage({
    roomId: action.roomId,
    payload: {
      tag: "Text",
      value: {
        text: body ? `Echo: ${body}` : `Usage: ${ECHO_COMMAND} <message>`,
      },
    },
  });
  if (result.isErr()) {
    throw new Error(
      `Unable to post the echo reply: ${JSON.stringify(result.error)}`,
    );
  }
}

async function copyDiagnosisReport(): Promise<void> {
  try {
    if (!globalThis.navigator?.clipboard?.writeText) {
      throw new Error("Clipboard API is unavailable");
    }
    await globalThis.navigator.clipboard.writeText(diagnosis.markdown());
    diagnosis.copied();
  } catch {
    // A standard native Chat text message already exposes the host's Copy menu,
    // so keep that as a reliable fallback when the worker has no clipboard.
    diagnosis.copyUnavailable();
    await postMessage({
      tag: "Text",
      value: { text: diagnosis.markdown() },
    });
  }
}

async function publishFinalReportIfComplete(): Promise<void> {
  if (!diagnosis.isComplete() || finalReportPosted) return;
  finalReportPosted = true;
  const result = await chat.postMessage({
    roomId: ROOM_ID,
    payload: { tag: "Text", value: { text: diagnosis.markdown() } },
  });
  if (result.isErr()) {
    diagnosis.fail(
      "Chat/post_message",
      `Unable to post the final report: ${JSON.stringify(result.error)}`,
    );
  }
}

async function postMessage(
  payload: Parameters<typeof chat.postMessage>[0]["payload"],
): Promise<string> {
  const result = await chat.postMessage({ roomId: ROOM_ID, payload });
  if (result.isErr()) {
    throw new Error(
      `Unable to post a Playground Chat message: ${JSON.stringify(result.error)}`,
    );
  }
  return result.value.messageId;
}

async function waitForRoom(
  observable: ObservableLike<HostChatListSubscribeItem>,
  roomId: string,
): Promise<void> {
  await firstValueFrom(
    from(observable).pipe(
      filter((item) =>
        item.rooms.some((candidate) => candidate.roomId === roomId),
      ),
      timeout({ first: 10_000 }),
    ),
  );
}
