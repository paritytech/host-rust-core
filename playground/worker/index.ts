import { getClientSync } from "@parity/truapi/sandbox";
import type {
  HostChatActionSubscribeItem,
  HostChatListSubscribeItem,
  ObservableLike,
  ProductChatCustomMessageRenderSubscribeItem,
} from "@parity/truapi";

const ROOM_ID = "truapi-playground";
const ROOM_NAME = "TrUAPI Playground";
const BOT_ID = "truapi-playground-bot";
const ECHO_COMMAND = "!echo";
const RENDER_MESSAGE_TYPE = "truapi-chat-api-check";
const RENDER_PAYLOAD =
  "0x637573746f6d5f6d6573736167655f72656e6465725f737562736372696265";

const client = getClientSync();
if (!client) {
  throw new Error("TrUAPI Playground Chat worker requires a host connection");
}
const chat = client.chat;

const room = await chat.createRoom({
  roomId: ROOM_ID,
  name: ROOM_NAME,
  icon: "",
});
if (room.isErr()) {
  throw new Error(
    `Unable to create the Playground Chat room: ${JSON.stringify(room.error)}`,
  );
}

const bot = await chat.registerBot({
  botId: BOT_ID,
  name: ROOM_NAME,
  icon: "",
});
if (
  bot.isOk() ||
  bot.error.tag !== "HostFailure" ||
  bot.error.value.reason !== "unavailable"
) {
  throw new Error(
    `registerBot no longer has the expected unavailable behavior: ${JSON.stringify(bot)}`,
  );
}

const renderer = chat.customMessageRenderSubscribe();
renderer.responses.subscribe({
  next(item) {
    handleRenderRequest(item);
  },
  error(error) {
    console.error("TrUAPI Playground custom renderer stream failed", error);
  },
});

const rooms = chat.listSubscribe();
await waitForPlaygroundRoom(rooms);

await postMessage({
  tag: "Text",
  value: {
    text: 'Chat API checks passed. Send "!echo <message>" to test actions.',
  },
});
await postMessage({
  tag: "Custom",
  value: {
    messageType: RENDER_MESSAGE_TYPE,
    payload: RENDER_PAYLOAD,
  },
});

chat.actionSubscribe().subscribe({
  next(action) {
    void handleAction(action).catch((error: unknown) => {
      console.error("Unable to handle the Playground Chat action", error);
    });
  },
  error(error) {
    console.error("TrUAPI Playground Chat action stream failed", error);
  },
});

function handleRenderRequest(
  item: ProductChatCustomMessageRenderSubscribeItem,
): void {
  if (item.messageType !== RENDER_MESSAGE_TYPE) {
    renderer.requests.next({
      tag: "Failed",
      value: { messageId: item.messageId },
    });
    return;
  }

  renderer.requests.next({
    tag: "Update",
    value: {
      messageId: item.messageId,
      node: {
        tag: "Text",
        value: {
          modifiers: [],
          props: {},
          children: [
            {
              tag: "String",
              value: {
                text: `${decodeHex(item.payload)}: passed`,
              },
            },
          ],
        },
      },
    },
  });
}

async function waitForPlaygroundRoom(
  observable: ObservableLike<HostChatListSubscribeItem>,
): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    const subscription = observable.subscribe({
      next(item) {
        if (item.rooms.some((candidate) => candidate.roomId === ROOM_ID)) {
          subscription.unsubscribe();
          resolve();
        }
      },
      error: reject,
      complete() {
        reject(new Error("Chat room list ended before returning the room"));
      },
    });
  });
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

async function handleAction(
  action: HostChatActionSubscribeItem,
): Promise<void> {
  if (action.payload.tag !== "MessagePosted") return;
  if (action.payload.value.tag !== "Text") return;

  const text = action.payload.value.value.text.trim();
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
    console.error("Unable to post the Playground Chat reply", result.error);
  }
}

function decodeHex(value: `0x${string}`): string {
  const bytes = value
    .slice(2)
    .match(/.{1,2}/g)
    ?.map((byte) => Number.parseInt(byte, 16));
  return new TextDecoder().decode(Uint8Array.from(bytes ?? []));
}
