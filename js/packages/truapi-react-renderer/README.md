# @parity/truapi-react-renderer

A custom React reconciler for rendering native UI widgets inside TrUAPI host applications. Use it to render interactive widget trees in response to custom chat messages.

## How it works

When the host app displays a custom chat message, it calls your product to produce a **widget tree** — a structured description of the UI to render natively (buttons, text, columns, etc.). This package implements a custom React reconciler that maps React components to that widget tree format ([`CustomRendererNode`](https://github.com/paritytech/truapi)), so you can use React features like `useState`, `useEffect`, and component composition to build your UI.

```
React component tree
      ↓  (React reconciler)
Widget tree (CustomRendererNode)
      ↓  (SCALE encoding)
Native Desktop/Mobile UI
```

All widget and style types come from [`@parity/truapi`](../truapi), the canonical TypeScript bindings for the TrUAPI protocol.

## Installation

```shell
npm install @parity/truapi-react-renderer react --save -E
```

## Setup

Configure your `tsconfig.json` to use React JSX:

```json
{
  "compilerOptions": {
    "jsx": "react-jsx"
  }
}
```

---

## `registerChatMessageRenderer`

The primary entry point for rendering custom chat messages. Pass a `mapPayload` function that decodes the raw bytes sent by the host, and a `renderFn` that returns the React element tree. The return value is a `ChatCustomMessageRenderer` callback you hand to your transport's custom message rendering request handler.

### Static message

```tsx
import {
  registerChatMessageRenderer,
  Text,
} from "@parity/truapi-react-renderer";

chat.onCustomMessageRenderingRequest(
  registerChatMessageRenderer(
    () => undefined,
    () => <Text style="HeadlineLarge">Hello from the product!</Text>,
  ),
);
```

### Decoding a payload

`mapPayload` converts the raw `Uint8Array` the host sends before your `renderFn` sees it. A common pattern is JSON:

```tsx
import {
  registerChatMessageRenderer,
  Column,
  Text,
} from "@parity/truapi-react-renderer";

type BalancePayload = { token: string; amount: string };

chat.onCustomMessageRenderingRequest(
  registerChatMessageRenderer(
    (raw) => JSON.parse(new TextDecoder().decode(raw)) as BalancePayload,
    ({ payload }) => (
      <Column>
        <Text style="HeadlineLarge">{payload.amount}</Text>
        <Text color="FgSecondary">{payload.token}</Text>
      </Column>
    ),
  ),
);
```

### Interactive messages

Use standard React hooks for local state. The library automatically wires up callbacks to user interactions on the host side.

```tsx
import { useState } from "react";
import {
  registerChatMessageRenderer,
  Column,
  Text,
  Button,
} from "@parity/truapi-react-renderer";

function VoteWidget() {
  const [votes, setVotes] = useState(0);
  return (
    <Column horizontalAlignment="Center" padding={16}>
      <Text style="HeadlineLarge">Votes: {votes}</Text>
      <Button
        text="Vote"
        variant="Primary"
        onClick={() => setVotes((v) => v + 1)}
      />
    </Column>
  );
}

chat.onCustomMessageRenderingRequest(
  registerChatMessageRenderer(
    () => undefined,
    () => <VoteWidget />,
  ),
);
```

### Using messageId and messageType

Both are forwarded to `renderFn` so you can adapt the UI per message:

```tsx
import {
  registerChatMessageRenderer,
  Text,
} from "@parity/truapi-react-renderer";

chat.onCustomMessageRenderingRequest(
  registerChatMessageRenderer(
    () => undefined,
    ({ messageId, messageType }) => (
      <Text color="FgSecondary">
        [{messageType}] {messageId}
      </Text>
    ),
  ),
);
```

---

## Components

All components accept the [shared layout props](#layout-props) in addition to their own props.

### `<Text>`

| Prop       | Type              | Description                  |
| ---------- | ----------------- | ---------------------------- |
| `style`    | `TypographyStyle` | Font style                   |
| `color`    | `ColorToken`      | Text color                   |
| `children` | `ReactNode`       | Text content or nested nodes |

**`TypographyStyle`**: `HeadlineLarge` · `TitleMediumRegular` · `BodyLargeRegular` · `BodyMediumRegular` · `BodySmallRegular`

```tsx
<Text style="HeadlineLarge" color="FgPrimary">
  Balance: 42 DOT
</Text>
```

### `<Button>`

| Prop      | Type            | Description             |
| --------- | --------------- | ----------------------- |
| `text`    | `string`        | Label (required)        |
| `onClick` | `() => void`    | Tap handler (required)  |
| `variant` | `ButtonVariant` | Visual style            |
| `enabled` | `boolean`       | Defaults to `true`      |
| `loading` | `boolean`       | Shows loading indicator |

**`ButtonVariant`**: `Primary` · `Secondary` · `Text`

```tsx
<Button text="Send" variant="Primary" onClick={handleSend} />
```

### `<TextField>`

| Prop            | Type                      | Description               |
| --------------- | ------------------------- | ------------------------- |
| `value`         | `string`                  | Current value (required)  |
| `onValueChange` | `(value: string) => void` | Change handler (required) |
| `placeholder`   | `string`                  | Placeholder text          |
| `label`         | `string`                  | Field label               |
| `enabled`       | `boolean`                 | Defaults to `true`        |

```tsx
<TextField value={query} placeholder="Search…" onValueChange={setQuery} />
```

`onValueChange` receives the decoded string value each time the user edits the field.

```tsx
import { useState } from "react";
import {
  registerChatMessageRenderer,
  Column,
  Text,
  TextField,
  Button,
} from "@parity/truapi-react-renderer";

function SearchForm() {
  const [query, setQuery] = useState("");

  function handleSubmit() {
    // send the query somewhere
  }

  return (
    <Column padding={16}>
      <TextField value={query} placeholder="Search…" onValueChange={setQuery} />
      <Button text="Search" variant="Primary" onClick={handleSubmit} />
    </Column>
  );
}

chat.onCustomMessageRenderingRequest(
  registerChatMessageRenderer(
    () => undefined,
    () => <SearchForm />,
  ),
);
```

### `<Column>`

Stacks children vertically.

| Prop                  | Type                  | Description          |
| --------------------- | --------------------- | -------------------- |
| `horizontalAlignment` | `HorizontalAlignment` | Cross-axis alignment |
| `verticalArrangement` | `Arrangement`         | Main-axis spacing    |

**`HorizontalAlignment`**: `Start` · `Center` · `End`
**`Arrangement`**: `Start` · `End` · `Center` · `SpaceBetween` · `SpaceAround` · `SpaceEvenly`

```tsx
<Column
  horizontalAlignment="Center"
  verticalArrangement="SpaceBetween"
  padding={16}
>
  <Text style="HeadlineLarge">Title</Text>
  <Button text="OK" onClick={handleOk} />
</Column>
```

### `<Row>`

Stacks children horizontally.

| Prop                    | Type                | Description          |
| ----------------------- | ------------------- | -------------------- |
| `verticalAlignment`     | `VerticalAlignment` | Cross-axis alignment |
| `horizontalArrangement` | `Arrangement`       | Main-axis spacing    |

**`VerticalAlignment`**: `Top` · `Center` · `Bottom`

```tsx
<Row verticalAlignment="Center" horizontalArrangement="SpaceBetween">
  <Text>Label</Text>
  <Text color="FgSecondary">Value</Text>
</Row>
```

### `<Box>`

Single-child container with optional content alignment.

| Prop               | Type               | Description                 |
| ------------------ | ------------------ | --------------------------- |
| `contentAlignment` | `ContentAlignment` | Alignment of the child node |

**`ContentAlignment`**: `TopStart` · `TopCenter` · `TopEnd` · `CenterStart` · `Center` · `CenterEnd` · `BottomStart` · `BottomCenter` · `BottomEnd`

```tsx
<Box contentAlignment="Center" background="BgSurfaceContainer" padding={8}>
  <Text>Centered</Text>
</Box>
```

### `<Spacer>`

Flexible space element. Use `fillMaxWidth` / `fillMaxHeight` or explicit `width` / `height`.

```tsx
<Row>
  <Text>Left</Text>
  <Spacer fillMaxWidth />
  <Text>Right</Text>
</Row>
```

---

## Layout props

Every component accepts these props to control sizing, spacing, and appearance.

### Spacing

| Prop      | Type      | Description   |
| --------- | --------- | ------------- |
| `padding` | `Padding` | Inner spacing |
| `margin`  | `Padding` | Outer spacing |

`Padding` is a single number (applied to all sides) or a `Dimensions` object: `{ top, end, bottom?, start? }` — `bottom` defaults to `top` and `start` defaults to `end` when absent.

### Sizing

| Prop            | Type      | Description                     |
| --------------- | --------- | ------------------------------- |
| `width`         | `Size`    | Fixed width                     |
| `height`        | `Size`    | Fixed height                    |
| `minWidth`      | `Size`    | Minimum width                   |
| `minHeight`     | `Size`    | Minimum height                  |
| `fillMaxWidth`  | `boolean` | Expand to fill available width  |
| `fillMaxHeight` | `boolean` | Expand to fill available height |

### Background

`background` accepts either a `ColorToken` string or a `BackgroundStyle` object:

```tsx
// Plain color
<Box background="BgSurfaceContainer" />

// Color + shape
<Box background={{ color: "BgSurfaceContainer", shape: { tag: "Rounded", value: { radius: 8 } } }} />
<Box background={{ color: "BgSurfaceNested", shape: { tag: "Circle" } }} />
```

### Border

```tsx
<Box border={{ width: 1, color: "FgTertiary" }} />
// With a rounded corner
<Box border={{ width: 1, color: "FgSuccess", shape: { tag: "Rounded", value: { radius: 4 } } }} />
```

---

## Color tokens

| Token                | Description                 |
| -------------------- | --------------------------- |
| `FgPrimary`          | Primary text                |
| `FgSecondary`        | Secondary / supporting text |
| `FgTertiary`         | Tertiary / hint text        |
| `BgSurfaceMain`      | Primary surface             |
| `BgSurfaceContainer` | Secondary surface           |
| `BgSurfaceNested`    | Tertiary surface            |
| `FgSuccess`          | Positive / success state    |
| `FgWarning`          | Warning state               |
| `FgError`            | Error / destructive state   |

---

## `createRenderer`

The low-level primitive that `registerChatMessageRenderer` is built on. Use it directly when you need to manage the renderer lifecycle yourself or integrate it into a custom pipeline outside of the chat system.

`createRenderer` returns an object with two methods:

| Method        | Description                              |
| ------------- | ---------------------------------------- |
| `mount(node)` | Mount or update the element tree         |
| `unmount()`   | Tear down the tree and release resources |

### Basic usage

```tsx
import {
  createRenderer,
  Column,
  Text,
  Button,
} from "@parity/truapi-react-renderer";

const renderer = createRenderer({
  // Called after every commit with the serialized widget tree.
  onRender(node) {
    send(node);
  },

  // Subscribe to events from the host.
  // Return an unsubscribe function.
  subscribeActions: (callback) => {
    return actionsSubscription.subscribe((actionId, payload) => {
      callback(actionId, payload);
    });
  },
});

// Mount the initial tree.
renderer.mount(
  <Column>
    <Text style="HeadlineLarge">Hello</Text>
    <Button text="OK" onClick={() => console.log("clicked")} />
  </Column>,
);

// Unmount when done — cleans up the React tree and unsubscribes from actions.
renderer.unmount();
```

### Re-mounting with new content

`mount` can be called multiple times to update the tree. React reconciles the difference, preserving component state where the component type is the same.

```tsx
// First render
renderer.mount(<Text style="HeadlineLarge">Loading…</Text>);

// Later — update in place
renderer.mount(<Text style="HeadlineLarge">Done!</Text>);
```

### Manual integration with a rendering request handler

This is what `registerChatMessageRenderer` does internally. Writing it manually gives you full control over the teardown sequence:

```tsx
import { createRenderer, Text } from "@parity/truapi-react-renderer";

chat.onCustomMessageRenderingRequest(
  ({ messageId, messageType, payload, subscribeActions }, render) => {
    const renderer = createRenderer({ onRender: render, subscribeActions });

    renderer.mount(<Text style="HeadlineLarge">{messageType}</Text>);

    // Return the cleanup callback.
    return () => {
      renderer.unmount();
    };
  },
);
```
