---
title: "Input Modality"
owner: "@johnthecat"
status: draft
---

# RFC-0028: Input Modality

|                 |                                                                                                   |
| --------------- | ------------------------------------------------------------------------------------------------- |
| **Start Date**  | 2026-07-28                                                                                        |
| **Description** | Route user input to the products already on screen, as a contextual surface over another modality |
| **Authors**     | Sergey Zhuravlev                                                                                  |

## Summary

Input is the modality through which a user hands something to the products while using them. It is served by a product's
worker, like Chat and Pocket, and unlike them it has no screen of its own. The host opens it as a surface on top of
whatever the user is already looking at, and **the screen underneath determines who must receive the input**. Those
products are always asked and their answers always rank first. A host may ask others beyond them, which is its own
policy call, and their answers rank strictly below. Each product answers with candidates or declines. A candidate the
host can draw it draws; one the product wants to own it asks the product to render, and controls inside it deliver
actions back. A navigation is the one exception — it names its own product and the surface to open, so it replaces the
context rather than acting within it. Workers are reference-counted and started by the host when something needs them.

## Motivation

A user looking at a product, or at a pocket full of several products' artifacts, has nothing to type into.

The protocol already streams plenty from host to product — room lists, balances, chain head, a peer's chat action. Every
one of those carries host or network state the product asked to watch, and arrives because the product subscribed to a
topic it named. None carries what the person in front of the host just typed, scanned, or shared, because there is no
topic for it: the user's own input has never been something a product could be told about.

Two capabilities are missing for the same reason:

- **A product cannot be handed anything.** The only way to reach one is to open it, so every input has to be an entry
  point: it names a product, the host launches it, and the launch _is_ the delivery. There is no channel to a product
  the user is already looking at.
- **A product cannot answer.** Every product holds state the host cannot see — an address book, a collection, an order
  history. A string may be meaningful to one of them and to nothing else, and there is no way to say so. The host cannot
  close this by learning more formats: the set of strings a user may type is open, and any list the core enumerates is
  stale on arrival.

Making input contextual closes both: the user opened a screen, the screen names its products, and those are the products
asked.

### Requirements

1. What is on screen is always asked and always ranks first. Whether anything beyond it is asked is the host's call.
2. Delivery to a product that is already running, and to one the host starts because the context needs it.
3. Nothing externally authored routed to any product before the user confirms it, and no typed text routed per
   keystroke.
4. A worker runs when something needs it and not otherwise.
5. A clear boundary between a product _seeing_ an input and a product _acting_ on one. Being asked authorises nothing;
   acting begins only when the user works a control the product drew.

### Scope note

Input capture needs nothing from TrUAPI: a camera, a text field, and a URL handler are host-local, and a scanned code is
just bytes. What the host does with the input afterwards is a product-facing contract, so this RFC adds wire methods to
`truapi`.

## Explanation

The user opens the input surface over the screen they are on — a product's app view, a chat with a product, a pocket of
several products' artifacts. The host reads that screen for its **context set**: the products present in it, which it
must ask and must rank first. Text goes to all of them at once and each answers with candidates or declines. Beyond them
the host may ask further products at its own discretion, ranked below. An attachment reaches exactly one product. A
navigation names a product and a place inside it outright, and moves there instead.

Five parts follow: the **registration** a product publishes to take part at all, the **data types** that fix what an
input is, the **context** that fixes who receives it, the **lifecycle** that fixes when their workers run, and the
**answering** that fixes what comes back. A list of corner cases closes it.

### Registration

Before any of the routing below applies to a product, its worker manifest has to say so. The
[Product Manifest Format](product-manifest.md) defines the worker executable at `worker.<product_id>.<tld>` and its
`includes` key, which already names `input` beside `chat` and `pocket`. This RFC gives `includes.input` its routing
semantics and adds one key beside it for attachments. A worker that declares neither is never asked anything.

```jsonc
{
  "kind": "worker",
  "entrypoint": "./worker.js",
  "includes": { "chat": true, "pocket": false, "input": true },
  "query": {
    "attachment": ["audio", "video", "image", "file"],
  },
}
```

- **`includes.input`** is a boolean defaulting to `false`, and governs text queries only. A worker without it is skipped
  when its context is queried, still serves whatever else `includes` declares, and still receives navigations addressed
  to it — a product is always reachable by name.
- **`query.attachment`** is an array of attachment categories, defaulting to empty. The members are `audio`, `video`,
  `image`, and `file` — the categories the wire carries, so a product declares in the same four terms a delivery arrives
  in, and eligibility is a set membership test rather than a pattern match. An unrecognized member is ignored rather
  than rejecting the manifest. An empty array and an absent key mean the same thing.

**The declaration names shapes, not content, and it only ever narrows.** There is deliberately no way to declare "I
answer SS58 addresses": text is one flag. A product can start answering a new class of string in a deploy with no
manifest change, and nothing it writes in the manifest can put it in front of a user who did not open it. What the
declaration governs is whether the host bothers to ask — and, for a product the user is not looking at, whether it may
be asked at all.

Each declaration admits a different shape of input: a string the user wrote, or a payload they handed over. Those shapes
are what the wire has to carry.

### Data types

#### The routed input

A routed input says one of two things: **open this surface of this product**, or **here is a query for the products in
context**.

```rust
/// What the host resolved a user input to.
pub enum RoutedInput {
    /// Open the product's app view at a path within it.
    App { product_id: String, path: String },
    /// Open one room of the product's chat view.
    Chat { product_id: String, room_id: String },
    /// Open one artifact in the product's pocket view.
    Pocket { product_id: String, artifact_id: String },
    /// Something to be answered, uninterpreted by the host. Text the host
    /// resolved to no product falls through to here.
    Query(Query),
}

/// An input no product was named for.
pub enum Query {
    /// The user's text, exactly as they entered it.
    Text(String),
    /// Something the user handed to the host, carried whole.
    Attachment(Attachment),
}

/// A user-supplied payload, categorized for handling.
pub enum Attachment {
    /// Audio the host can play inline.
    Audio(AttachmentData),
    /// Video the host can play inline.
    Video(AttachmentData),
    /// An image the host can render inline.
    Image(AttachmentData),
    /// Anything else — a document, an archive, an unrecognized type.
    File(AttachmentData),
}

/// The bytes of an attachment and what they are.
pub struct AttachmentData {
    /// Name as the user knows it.
    pub file_name: String,
    /// MIME type.
    pub mime_type: String,
    /// The bytes themselves.
    pub content: Vec<u8>,
}
```

The first three variants carry their own context: they name a product and a surface, so the host opens it and the screen
changes. `Query` carries none, so it inherits the context it was entered in. On the three navigation variants
`product_id` rides along even though the recipient knows its own name, so that a delivery is complete on its own and can
be checked against the product it was meant for.

**Query text crosses unmodified.** The host's only decision about a string is which variant it becomes; once it is
`Query::Text`, every product the host queries receives exactly what the user entered. No normalization, no tokenization,
no spelling correction, no language detection, no stripping. Interpreting a string is the answering product's job.

The attachment category is derived, not declared: the host maps `image/*`, `audio/*`, and `video/*` to their variants
and everything else to `File`. `mime_type` is never empty — a host receiving a type-less attachment from the operating
system substitutes `application/octet-stream`. The category says how the payload is _labelled_, not what the bytes are,
because the label came from the same source as the bytes. Dispatch on the category, validate before decoding.
`file_name` and `mime_type` ride alongside the bytes because four categories are enough to decide _what to do_ with a
payload and not enough to decode one.

#### The input syntax is not specified here

This RFC fixes what a routed input _is_, not the textual form a user types or a code carries. It is silent on the URL
scheme, on how a modality is addressed, and on how a product identifier is spelled inside a link. The cost: until a
syntax exists, two hosts may classify the same printed code differently, so it blocks anything printed or shared between
hosts.

Two things bind the host in the meantime. The fallthrough is normative: an input the host cannot resolve to a product is
`Query::Text`, never promoted to a navigation. And a later syntax may only claim input the fallthrough was carrying,
never reclassify input that already resolved to a product.

#### When routing happens

Routing is gated, and the gate differs by how the input arrived. **The split is the same one provenance draws: input the
user produced inside the host flows as they work, input authored outside it moves only on an explicit confirmation.**

- **Composed by the user.** The host routes on a debounce — a pause in typing, not a keystroke and not a submit. Rounds
  supersede, so what the user sees is the answer to the string currently in the field.
- **Scanned.** The host shows what it decoded and what it will do with it, and routes only on confirmation. This is
  normative. A camera decoding continuously never routes on its own.
- **From the operating system.** Same, and normative for the same reason. The tap that delivered it is not consent — the
  user saw a link, not a payload. A share sheet or file picker satisfies the gate on the host's behalf: the OS surface
  showed the user the payload and asked where to send it, so the host confirms again only when what arrived was a bare
  tap.

#### Provenance

Every delivery carries where the input came from, so a product can hold outside input to a stricter standard than input
the user composed inside the host.

```rust
/// Where the input came from.
pub enum InputSource {
    /// Composed by the user inside the host — typed into an input field,
    /// dictated, or otherwise authored on the spot.
    User,
    /// Read from a camera or an image (QR, barcode). Externally authored.
    Scanned,
    /// Handed to the host by the operating system — a URL handler firing, a
    /// notification tap, a link followed from another application, a share
    /// sheet, a drag-and-drop, a file picker. Externally authored.
    OperatingSystem,
}
```

**The split that matters is externally authored versus user-originated**, and it runs between `User` and the other two.
A printed code, a link fired through the OS handler, and a file the user picked all carry content someone else chose;
none is safer than the others, and a product must not auto-execute on any of them. A product that branches only on
`Scanned` has a hole exactly the size of a hostile web page. Satisfying the gate does not move an input across the
split: what the user confirmed — by tapping through, or by picking a file from a share sheet — is that the host may
proceed and where the bytes should go, never that they authored the payload.

The set grows as hosts gain modalities. A source added later must state which side of the split it falls on; the default
is externally authored. There is no `Product` source — nothing here routes input from one product to another.

#### Semantic query types are deferred

An SS58 address, an extrinsic hash, a referendum number, and a payment URI all arrive as `Query::Text`. The products in
context do the interpreting.

Promoting a format to a variant makes the core the arbiter of that domain and obliges every host to upgrade before it
can route the format at all. Such a variant can join `Query` later, claiming input `Text` already carries.

### Context

#### The context set

**The products on screen are the products that must be asked.** The host derives a set of product identifiers from the
modality the input surface opened over, and that set is a floor, not a ceiling: every product in it is queried and its
answers rank above anything else, while whether the host looks further is the host's own decision.

| Modality underneath | Context set                                        |
| ------------------- | -------------------------------------------------- |
| App                 | The one product whose app view is on screen.       |
| Chat                | The one product whose chat view is on screen.      |
| Pocket              | Every product with an artifact in the pocket view. |

Two properties make the set worth deriving. **The user assembled it by navigating** — opening a screen is what puts its
products in scope, directly for an app or chat view and through contributed artifacts for a pocket. And **it is small
and known in advance**: one product for app and chat, and for a pocket exactly the products the host already enumerated
to render the view.

Widget is not specified here (Q1): until it is, the input surface does not open over a dashboard.

#### Beyond the context

A host may query products outside the context set. Three rules bound it, and all three are normative.

- **Context first, always.** Every product in the context set is queried, and no host policy may drop one to make room
  for an outside product. The floor cannot be traded away.
- **Outside answers rank strictly below.** A candidate from a product not in context is displayed after every context
  candidate, however confident its product claimed to be. Ranking _within_ each band is host policy; the boundary
  between the bands is not.
- **Only declaring products are eligible.** `includes.input` is how a product consents to being asked by users who are
  not looking at it. A host may not add a product that has not published it.

Which products a host asks beyond the floor, and whether it asks any at all, is unspecified. A host that asks none is
conformant. A host may ask the products a user selects most often, the ones that answered this shape of input before, or
nothing at all; these are user-agent decisions. What the extension costs in disclosure is stated under Security.

#### Asking in a chat is not sending a message

Chat is where the input surface most obviously overlaps something that already exists, so the boundary is normative. **A
query put to a product from its chat view is not a message in the conversation.** It does not enter the transcript, the
product is not expected to reply as a participant, and the candidates are rendered and then discarded. A message is a
durable turn addressed by id, subject to edits and replies; a query is transient. Asking "which of these did I pay for"
over a chat no more adds to the conversation than find-in-page adds to a page.

A product that wants a query to become part of the conversation posts a message through the chat API, on its own
initiative and through its own surface. The host never does it on the product's behalf, and nothing about a query —
including which candidate the user picked — reaches the transcript by itself.

#### Contextual routing

`Query::Text` goes to every product in the context set at once, plus whatever the host adds beyond it. In an app or chat
context the floor is one product and one answer; in a pocket it is a small fan-out the host ranks.

A product whose worker manifest omits `includes.input` is skipped either way, and the omission means two different
things depending on the band. Inside the context the declaration is an efficiency hint — the product is on screen
regardless, and the flag saves the host starting a worker to be told `NotHandled` every time. Outside it, the
declaration is the whole of the product's consent to be asked at all: it is what a product publishes to say it is
willing to answer for users who are not looking at it. Nothing the declaration says can put a product in the context
set, which is fixed by the screen alone.

#### Escaping the context

`App`, `Chat`, and `Pocket` name a product outright, along with the one place inside it to land — a path, a room, an
artifact. They do not consult the context set and are not delivered to it: the host navigates to the named surface,
replacing the screen the input surface opened over. A navigation carries its own context, so the confirmation gate
matters most here: a scanned code that navigates is the only input that can move the user somewhere they did not choose.

A navigation targets whichever executable serves the named surface — the app executable for `App`, the worker for `Chat`
and `Pocket`, whose `includes` must declare that surface. The host holds the delivery until that executable is running
and can be called, or until the navigation deadline elapses, after which it discards the delivery and shows its own
message. A navigation is the one delivery that survives the screen it was entered on, so the context change it causes
does not supersede it.

#### Attachment queries

**An attachment is delivered whole, to exactly one product, and never fanned out.** `content` is the bytes themselves,
so every delivery hands the payload over completely. `query.attachment` decides which products are eligible — those that
declared the category the host derived for the payload — and the count decides what happens:

- **One eligible product.** The host delivers to it.
- **Several.** The host presents a picker, context products first, and delivers to the one the user picks.
- **None.** The host shows the same empty state any unanswerable query gets. No bytes leave the host.

**The eligible set may extend beyond the context.** A text query discloses on the _ask_: every product queried learns
the string. An attachment discloses on the _pick_: listing a product in a picker tells it nothing, and the bytes move
only after the user names one recipient. A host that would not query an out-of-context product with text can still list
it here.

### Lifecycle

#### Reference-counted workers

**A worker runs because something holds a reference to it, and the host starts it when the first reference is taken.** A
product does not publish a worker to keep a process alive; it publishes one so the host has something to start when it
needs an answer. This governs the worker executable only — an app executable's lifetime is its screen, and nothing here
changes that.

References come from the things that need a worker running:

- An **open input surface**, on every product in its context set, and on any product it queries beyond that for as long
  as that round is open.
- An **open pocket or chat surface**, on each product serving it.
- A **pending navigation** to `Chat` or `Pocket`, until the delivery lands or the navigation deadline elapses.
- A **displayed `Custom` candidate**, on the product drawing it, for as long as its render call is open.

When the count reaches zero the host may stop the worker.

Two consequences are normative. A worker **must tolerate being stopped whenever nothing holds a reference to it**, which
can happen while its answer is still on screen — an outside product's reference ends with its round, though its
candidate stays in the list. Only a `Custom` candidate keeps its product running for as long as it is drawn. And a
worker **must not treat being started as a signal that the user did anything**: the host starts it when a context forms,
which may be before any input exists.

Starting is therefore routine, and it happens where the user is already waiting for a screen. Opening a pocket starts
the workers behind its artifacts, so an input surface opened over it a moment later finds them running. The race that
remains is a user who types faster than a worker starts; the hard deadline resolves it against the worker.

### Answering

**The host calls the product and the product answers.** A routed input travels as a call to the product, and the call's
return value is the answer. Queries reach a product's worker; a navigation reaches whichever executable serves the named
surface, which is the app executable for `App`. Nothing correlates a response to a request, because the call _is_ the
correlation.

Only a `Query` calls for an answer; for a navigation the product completes the call without emitting. An attachment
query answers like any other query. Its round has one recipient, so the candidate list is that product's alone.

```rust
/// One input the host routed to this product.
pub struct ProductInputRequest {
    /// Where the input came from.
    pub source: InputSource,
    /// What was routed.
    pub input: RoutedInput,
}

/// What a product has to say about one query.
pub enum InputResponse {
    /// The product has nothing to offer. The ordinary answer, not an error.
    NotHandled,
    /// Zero or more answers, ordered by the product's own confidence.
    Candidates(Vec<InputCandidateContent>),
}
```

`NotHandled` is a normal response, cheap to produce and cheap to receive. It is not an error, does not appear as a
failure in host telemetry, and carries no penalty. A product that returns nothing at all before the deadline is treated
the same way.

Everything the host enforces — the deadlines, the candidate cap, the payload cap, supersession — it enforces by
discarding an answer or ending the call, so no error type crosses the wire in this direction. A product cannot fail a
query; it can only be too slow, too large, or too late, and each of those is the host's to absorb.

#### Candidate content

```rust
/// Richer body for a candidate.
pub enum InputCandidateContent {
    /// Plain text.
    Text(String),
    /// Text with media attachments.
    RichText(InputRichText),
    /// A file the candidate offers.
    File(InputFile),
    /// A candidate the product draws itself.
    Custom(InputCustomContent),
}

/// A candidate whose body the product renders and whose controls it handles.
pub struct InputCustomContent {
    /// Identifies this candidate among the ones this product answered with.
    /// Correlates the render call and any action triggered in it.
    pub candidate_id: String,
    /// Product-defined discriminator used to select a renderer.
    pub content_type: String,
    /// Product-defined payload, opaque to the host.
    pub payload: Vec<u8>,
}

/// Text with media attachments.
pub struct InputRichText {
    /// Optional body text.
    pub text: Option<String>,
    /// Media rendered alongside the text.
    pub media: Vec<InputMedia>,
}

/// One media attachment.
pub struct InputMedia {
    /// Media URL.
    pub url: String,
    /// Alternative text. A host can only render the media accessibly when
    /// the product supplies it.
    pub alt: Option<String>,
}

/// A file a candidate offers.
pub struct InputFile {
    /// File name shown to the user.
    pub file_name: String,
    /// MIME type.
    pub mime_type: String,
    /// Size in bytes, so a host can warn before a large download.
    pub size_bytes: u64,
    /// Download URL, fetched only if the user takes the offer.
    pub url: String,
}
```

A candidate's file carries a URL rather than bytes, unlike an `Attachment` shared _into_ the host. The asymmetry follows
the cost: an attachment has one recipient already chosen, so sending it whole costs one transfer; a candidate is one of
several the user is still scanning, so fetching only on acceptance keeps the unpicked ones free. `InputFile` is
uncategorized because nothing declares against categories.

These shapes parallel what a chat message carries but are their own types: chat content addresses message ids and
carries reactions, edits, and replies, none of which apply to a candidate.

**The host supplies the frame, and identity is never the candidate's to choose.** Every candidate renders under the
answering product's `displayName` and `icon` from its root manifest, so a candidate cannot present itself as coming from
another product. `Text` is the whole answer for most candidates, and `Text`, `RichText`, and `File` are drawn by the
host from their content alone.

**A `Custom` candidate is drawn by the product.** Its `content_type` and `payload` are both opaque, so instead of
interpreting them the host hands them back and asks for a renderer tree, which it draws inside the frame it controls.
Such a candidate may carry controls, and pressing one delivers an action to the product. This is where a candidate stops
being a static answer and becomes something a product can act on.

#### The three methods

Answering is one exchange with two optional continuations, appended to the `System` trait. The shape is the one `Chat`
already uses for custom messages: a host-initiated call for content, a host-initiated call to render what the host
cannot draw, and a subscription carrying back what the user did to it.

```rust
/// Route one user input to this product and take its answer.
#[wire(host_initiated, start_id = 164)]
fn input_request(
    &self,
    _cx: &CallContext,
    _request: ProductInputRequest,
) -> Subscription<InputResponse>;

/// Stream renderer trees for one custom candidate.
#[wire(host_initiated, start_id = 168)]
fn input_custom_render(
    &self,
    _cx: &CallContext,
    _request: ProductInputCustomRenderRequest,
) -> Subscription<CustomRendererNode>;

/// Subscribe to actions the user triggered inside this product's candidates.
#[wire(start_id = 172)]
async fn input_action_subscribe(
    &self,
    _cx: &CallContext,
) -> Subscription<HostInputActionSubscribeItem>;
```

```rust
/// A custom candidate the host needs drawn.
pub struct ProductInputCustomRenderRequest {
    /// The candidate being rendered.
    pub candidate_id: String,
    /// The candidate's discriminator, as the product supplied it.
    pub content_type: String,
    /// The candidate's payload, as the product supplied it.
    pub payload: Vec<u8>,
}

/// An action the user triggered inside a custom candidate.
pub struct HostInputActionSubscribeItem {
    /// Candidate carrying the action.
    pub candidate_id: String,
    /// Which action was triggered, as named in the renderer tree.
    pub action_id: String,
    /// Optional additional data, as the renderer tree carried it.
    pub payload: Option<Vec<u8>>,
}
```

Each method mirrors one of `Chat`'s: `input_request` and `input_custom_render` are `host_initiated`, the existing
primitive for the host calling a product and taking a stream, and `input_action_subscribe` is an ordinary product→host
subscription like `Chat::action_subscribe`. `CustomRendererNode` is the tree `Chat::custom_message_render` already
returns, reused, so it needs re-exporting as a shared type.

A product answers `input_request` by emitting one `InputResponse` and completing. The stream shape is what lets it
revise an answer while the round is open, and what lets the host end the call on supersession or the hard deadline
without inventing a cancellation path. `input_custom_render` behaves the same way and stays open for as long as the
candidate is displayed, so a product can redraw a candidate in place — a balance that updates, a state that resolves.

`candidate_id` is minted by the product and is opaque to the host. It does what `message_id` does in chat: name one
drawn thing so a render call and an action can both point at it. A product answering with several custom candidates
needs it to know which the user pressed; `content_type` says which renderer draws a candidate, never which candidate it
is.

The host scopes a `candidate_id` to the product that minted it and to the round it was answered in. Products are
mutually untrusted, so two of them may pick the same string, and one must never be able to address the other's candidate
by guessing it. Reuse across rounds is a product's own affair — the host resolves an action against what it is currently
drawing.

A subscription consumes four consecutive ids. `CoinPayment::payment_received_subscribe` occupies 160–163 and `Locale`
holds 194 onward, so 164–167, 168–171, and 172–175 are unallocated. Codegen confirms the exact allocation.

Reference counting needs no wire surface of its own: a worker observes its lifecycle as its own process starting and
stopping.

#### Bounds

All host-enforced. The context set bounds the floor structurally — one product in an app or chat context, the pocket's
membership otherwise — and the caps below bound what a host adds to it, plus frequency, time, and size.

- **Debounce interval.** `User` text starts a round only after _D_ of no further input, so a round costs a pause rather
  than a keystroke.
- **Context cap.** At most _N_ products are queried from one context. This binds only on a large pocket; a
  single-product context can never reach it.
- **Extension cap.** At most _E_ products are queried beyond the context set. This is the bound that keeps a host's own
  policy from turning a query into a sweep of everything installed, and _E_ = 0 is conformant.
- **Soft deadline.** Candidates arriving after it are still accepted and merged into the displayed list.
- **Hard deadline.** Outstanding `input_request` calls are ended and late responses discarded. This is also the bound on
  a worker still starting when the round began. It does not bound a render call, which lives with the candidate it draws
  rather than with the round.
- **Candidate cap.** At most _M_ candidates per response; the excess is discarded, unlike an oversized response, which
  is dropped outright.
- **Payload cap.** A response over _B_ encoded bytes is dropped whole rather than truncated, and the product is treated
  as having answered nothing.
- **Attachment cap.** An attachment over _F_ bytes is declined before delivery — it crosses the wire whole, so its size
  is the message size.
- **Render cap.** At most _R_ `Custom` candidates are drawn at once. Each holds a render call and a worker reference, so
  this is the bound on how much a list of answers can cost to keep on screen; candidates past it render as the product's
  identity alone until one ahead of them leaves the list.

Recommended defaults, unvalidated (Q11): D = 250 ms, N = 16 products, E = 0, a 500 ms soft deadline, a 3 s hard
deadline, M = 8 candidates, B = 64 KiB per response, and R = 4 concurrently drawn custom candidates. _E_ defaults to
zero so a host decides to disclose beyond the screen rather than inheriting it. _F_ has no recommendation: it follows
from the host's message size limit, which differs by an order of magnitude between desktop and mobile. Only the presence
of each bound is normative.

**Rounds supersede.** The host ends an open round's calls before starting the next and displays only the latest round's
candidates, so a user typing sees the answers to what is in the field rather than a list accumulating stale results.
`CallContext` already carries cancellation and subscription interrupt is already in the wire protocol, so no new
mechanism is needed. Anything arriving on a call the host has ended is discarded without being merged.

### Corner cases

- **Nothing can answer a query.** One rule covers every way this happens: an empty context set, no product declaring the
  shape that arrived, or nobody answering in time. The host shows its own empty state and the input goes nowhere. This
  is the same outcome for text nobody claimed and for an attachment no product declared a category for — in the
  attachment case no bytes leave the host, since eligibility is decided before delivery. An empty result is not licence
  to widen past the extension cap, to fall back to a web search, or to navigate to the raw input.
- **The screen changes while a round is open.** The host interrupts it as a supersession. Candidates from a context the
  user has left are never merged into a new one. Clearing the field does the same, and an empty field starts no round.
- **A product in context is not running when the round starts.** The host starts it and calls it anyway, letting the
  hard deadline decide: a worker still starting has until then to answer, and one that never answers is
  indistinguishable from one that declined. A worker that crashes or fails to start loses its slot, and the round
  completes with the rest.
- **A worker answers more than once, late, or never.** The latest response received before the round closes is the one
  displayed, so a product may revise its answer while the round is open; anything after the hard deadline is discarded,
  and silence is treated as `NotHandled`. An oversized response is dropped whole rather than truncated. A revision
  replaces the answer entirely: any render call for a candidate that is no longer in it ends with the candidate, and its
  reference is released.
- **A navigation names a product that is not installed**, or a `Chat`/`Pocket` surface its worker does not serve.
  Declined with a host-owned message, leaving the context underneath alone. The host does not install a product to
  satisfy a navigation, and there is no fallback to the app view.
- **A candidate's content fails to render** — unreachable URL, or bytes not matching the declared MIME type. It stays in
  the list, rendered from whatever text it carries plus the product's identity. A failed fetch degrades a candidate,
  never removes it.
- **A `Custom` candidate's render call returns nothing, fails, or takes too long.** The host draws the product's
  identity with no body and invents no label. A product that no longer recognizes its own `content_type` answers with an
  empty tree rather than failing.
- **A product draws a `Custom` candidate with no open action subscription.** The host draws it regardless and discards
  actions it cannot deliver. Subscribing is the product's responsibility and belongs with starting, not with answering.
- **An action is triggered after the round closed**, or on a candidate the host has stopped drawing. The host does not
  deliver it: an action is only ever sent from a candidate currently on screen, so a product never has to reason about
  acting on a screen the user has left. A worker stopped between drawing and pressing cannot occur, since drawing holds
  a reference.
- **A product cannot use an attachment it was given.** Eligibility is a declared category, not a promise about the
  bytes, so a product may still find the payload unusable. It says so through its own interface, or answers
  `NotHandled`.
- **The user dismisses a scan or OS confirmation.** Nothing is routed and no product learns the input existed.

## Drawbacks

- **The same string typed over two screens gets two answer sets**, with nothing in the interface explaining why. The
  floor is what makes results predictable; it is also what makes them screen-dependent.
- **The disclosure surface is a host decision, so it varies between hosts.** A product cannot know how widely its users'
  input travels, and a user moving between hosts gets the same protocol with materially different privacy.
- **Fan-out returns wherever the set is large** — a big pocket, or a generous extension cap. The user gets a
  partially-queried result set with no indication of which products were skipped.
- **A product's answers depend on how fast it starts.** A product still launching when the user types misses the round;
  the hard deadline resolves the race against it.
- **Debounced typing discloses prefixes** to the products on screen, not only finished strings. Confirming externally
  authored input costs a step on exactly the flows that feel like they should be instant.
- **A `Custom` candidate keeps a worker alive while it is on screen**, so a list of them holds several workers running
  that a list of static candidates would have let go.
- **Three subscriptions consume twelve wire ids**, which are `u8` and never reused, and two of the three methods exist
  only for `Custom` candidates.

## Testing, Security, and Privacy

### Testing

- **The floor**, the assertion the whole design rests on: every product in the context set is queried, and none is
  dropped for an outside product however the host is configured. With the extension cap at zero, a query over an app or
  chat view reaches that product and nothing else, and a query over a pocket reaches exactly the products with artifacts
  in it.
- **The band boundary**: with the extension cap above zero, every context candidate is ordered before every outside
  candidate, whatever confidence each product claimed; and a product not declaring `includes.input` is never added to
  the outside band.
- **The chat boundary**: a query over a chat view produces an input delivery and no chat message, leaving the transcript
  unchanged whether or not the product answers.
- **Context changes**: navigating away mid-round interrupts it, and no candidate from the old context appears in the new
  one.
- **Reference counting**: a worker starts when its first reference is taken and not before; it is eligible to stop when
  the last is released; a round whose worker was not running starts it and still completes within the hard deadline.
- **The gates**: a decoded code produces no delivery until confirmation and none at all if dismissed; an OS-delivered
  payload produces none before its confirmation; a burst of keystrokes shorter than _D_ produces exactly one round; each
  new round interrupts the open one; a cleared field starts none.
- **Text passthrough**: a query carrying leading and trailing whitespace, mixed case, combining characters, and an emoji
  arrives byte-identical.
- **The declaration filter**: a product in context without `includes.input` is skipped; one declaring `["image"]` is
  offered a `image/png` attachment and not a `application/pdf`; one declaring `["file"]` is offered the PDF and not the
  image; an unrecognized category in the array is ignored and the rest of the declaration still applies.
- **The navigation boundary**: for a table of inputs, `parse_navigate` returns what it returned before this RFC.
- **Attachments**, the one invariant whose failure discloses user data: sharing one produces exactly one delivery, to
  the sole eligible product or to the one picked from several, and no delivery carrying those bytes reaches any other
  product in context. Alongside it — an oversized attachment is declined before delivery, and an unrecognized or absent
  MIME type lands in `File` rather than a guess.
- **Candidate rendering**: a list renders with no network activity whatever content it carries, and a candidate whose
  media URL 404s still renders.
- **The custom round trip**: a `Custom` candidate produces exactly one render call carrying its `content_type` and
  `payload` byte-identically; an action triggered in the tree it returns arrives on that product's own subscription
  under the same `candidate_id`; two candidates sharing a `content_type` stay distinguishable; and no action ever
  reaches a product that did not draw the candidate.

### Security and privacy

**Context sets a floor on relevance, not a ceiling on disclosure.** The privacy property is conditional: **a host that
queries only the context set discloses an input to nothing the user cannot see; a host that extends beyond it discloses
in proportion to how far it extends.**

Three properties hold unconditionally:

1. **The floor cannot be traded away.** Every product on screen is asked and ranks first. No policy, declaration, or
   outside product displaces one.
2. **Nothing but the input crosses.** A delivery carries the source and the routed input, and nothing else. No account,
   no identity, no history, no other product's data — and no indication of who else was asked or whether the recipient
   was in context.
3. **The user produced it, or confirmed it.** A query is either something the user typed into the host's own field or
   something they were shown and accepted. Nothing routes on a keystroke, a camera frame, or an OS handler firing on its
   own.

Two things bound what the extension can cost. A product is eligible only if it published `includes.input`, so the
outside band is the intersection of what the user installed with what those products asked to be asked; and the
extension cap bounds how many are reached in one round. Neither makes the disclosure visible to the user, which is the
part ranking does not fix — **ranking governs what an outside product may show, never what it was told.** A product
ranked last still learned the string.

The claim is weakest for a pocket. Its context set is every product that contributed an artifact, and an artifact may be
scrolled out of view or belong to a product the user has not thought about in weeks. What holds is that they opened that
pocket and the host can show them what is in it; not that they had each product in mind when they typed. Debouncing
sharpens this: what leaves the host is prefixes, not only finished strings.

A host has two mitigations available without any protocol change, and both belong at the user-agent layer where the
extension decision already lives: show which products are being queried, and let a user exclude one.

**A query is a disclosure, not an execution.** Putting one to products in context needs no per-request consent: nothing
user-visible happens, nothing is signed, no funds move, no screen opens. A product learns a string and answers or
declines; a candidate is data until the user works a control in it.

_Acting on a candidate needs the consent already defined elsewhere._ An action tells a product that the user pressed
something it drew, and nothing more — it grants no capability. Whatever the product does next it does through an API
carrying its own confirmation: signing under RFC-0002's remote permissions, payments under the payment API's, navigation
under `navigate_to` and `OpenUrl`. This RFC adds no consent primitive because an action can only wake the product that
drew the candidate, on a screen the user is looking at, in response to something the user pressed.

A `Custom` candidate is the one place a product controls pixels inside the host's surface, so the host keeps the frame:
identity, bounds, and dismissal are host-drawn around a tree the host interprets, never a surface the product paints
into. The renderer tree is a fixed vocabulary of nodes rather than markup, which is what makes the host's frame
enforceable.

**An externally authored payload is fully attacker-chosen**, which is why `InputSource` is on the wire.
`OperatingSystem` is the same case as `Scanned`: a link on a hostile page reaches the host through the OS handler, and a
tap is not evidence of authorship. The confirmation makes this visible rather than safe — it defeats a payload that
relies on never being seen, and nothing else. A product must treat either source as untrusted.

A navigation is where such a payload does the most, being the one input that can move a user into a context they did not
choose. Within routing, an unresolvable input becomes `Query::Text` and is never promoted to a navigation, so a merely
URL-shaped string cannot reach a product as something navigable. What routing cannot promise is that such a string never
reaches `navigate_to` at all — that is `NavigateDecision`'s question, answered by a classifier this RFC does not touch.

**Candidate spoofing is structurally prevented.** A candidate carries no icon and no identity of its own; the host
renders it under the answering product's manifest identity. A malicious product in a shared pocket can write any text,
but cannot present it as coming from another product in that pocket — the attack that matters, a fake "Official Wallet —
send funds" entry sitting next to real ones.

**An attachment is the most sensitive thing this RFC routes.** It carries its contents, so no fan-out discloses less
than everything, which is why there is none: exactly one product receives it, and the declaration narrows the eligible
set without ever widening it. The category carries no privilege — a host must not treat `Image` as a licence to render
bytes it has not validated, since the label is a claim about the label and not the bytes.

**Candidate content is where a query leaks back out.** Fetching a URL from `InputRichText` or `InputFile` tells its
server that this user saw this candidate. Two rules contain it: remote references are never fetched to render the list,
so a round produces no outbound requests at all; and a fetch happens only on expand or select, the same disclosure the
user makes by opening that product. Hosts fetch under the existing scheme allowlist and render media through a sandboxed
surface. What remains is size, bounded by the payload cap.

**Resource exhaustion is bounded by construction.** An input reaches at most the screen's products plus the extension
cap, and no payload can widen either — a malicious scanned code cannot choose who is asked, only what they are asked. It
either names one product and navigates, subject to confirmation, or becomes a query to the same set the user's own
typing would have reached. Reference counting bounds the other side: a worker runs while something needs it, so visiting
screens cannot accumulate background processes.

## Performance, Ergonomics, and Compatibility

### Performance

A single-product query — app or chat, with no extension — is one call out and one back, the cheapest shape this design
has. A pocket query costs up to N concurrent calls, and any extension adds up to E more, all bounded by both deadlines
and rendered incrementally at the soft deadline. Extension is also where cold starts concentrate, since an outside
product has no screen open to have started it. The debounce means cost scales with pauses in typing rather than
keystrokes, and supersession means at most one round is ever in flight.

A `Custom` candidate costs a second call per candidate and keeps it open while drawn, which is why the render cap exists
and why a product should answer with content the host can draw when it has no reason not to. The cost is paid per
candidate on screen rather than per query, so it scales with what the user is looking at.

Reference counting moves the launch cost off the query path and onto navigation: opening a pocket starts its workers, so
a round entered a moment later finds them running. That cost is paid where the user is already waiting for a screen, and
bounded by the same lifecycle that reclaims it. A user who types faster than a worker starts pays it on the query path
after all, bounded by the hard deadline. An attachment costs one delivery carrying the payload and one answer back.

### Ergonomics

A product participates by setting `includes.input` and implementing one method, then answering `NotHandled` for anything
it does not recognize. The other two are needed only by a product that draws its own candidates. What a product
_answers_ needs no declaring or re-publishing; only a change to the shapes it accepts costs a manifest publish.

The floor is low — a worker returning `Text` has a working, well-rendered candidate — and richer variants are opt-in.
Reference counting means a product does not have to reason about process lifetime: it answers what it can and tolerates
being stopped. A product answering with static content is done when it has answered; one answering with a `Custom`
candidate runs for exactly as long as the host is drawing it.

### Compatibility

`System::navigate_to` is untouched: `NavigateDecision`, its `canonical_url`, and `parse_navigate` keep their shapes and
behaviour, so no call site moves. Nothing existing is reinterpreted, because this RFC defines no input syntax.

The new wire methods are additive. A product that implements none of them receives no routed input; one that implements
only `input_request` answers with static content and never hears from the other two; a host that calls none changes
nothing for any product. The `query` manifest key is optional, so existing worker manifests stay valid.

## Prior Art and References

- The [Product Manifest Format](product-manifest.md), whose modalities, `includes`, and worker executable at
  `worker.<product_id>.<tld>` supply both the context sets and the thing being reference-counted.
- RFC-0002 (Permission Model), whose `OpenUrl` device permission governs a product's own external navigation.
- `Chat::custom_message_render`, the existing `host_initiated` method both calls here are shaped after: the host sends a
  request payload to a product and takes back a stream. It asks for a rendering of something the host already stored;
  this asks what a product makes of something the user just entered.
- `Chat::action_subscribe`, whose shape `input_action_subscribe` copies: a stream over which the host hands a product
  something a person did to something it drew. It carries a remote peer's action in a room; this carries the local
  user's action on a candidate, and needs no peer because the actor is always the person at the host.
- `ChatMessageContent` and the chat message codec in `@parity/host-chat`, the closest existing model for a product
  handing the host something to display.
- Android implicit intents, whose MIME-typed filters are the closest analogue to `query.attachment`, coarsened here to
  four categories — and whose action and URI-pattern filters are deliberately not adopted, because a filter over content
  cannot enumerate an open query space.
- Android bound services, whose client-count lifecycle is the model for reference-counted workers.
- macOS Spotlight and the browser omnibox, which must decide who might answer with nothing on screen to derive it from.
  A context set removes that guess; a host extending past its floor takes it back on.

## Unresolved Questions

1. **The Widget context.** A dashboard might contribute every product with a widget on it, which is close to an
   installed-set broadcast wearing a context's clothes, or only the widget the user opened the surface from. Until this
   is settled the input surface does not open over a dashboard.
2. **Multi-product conversations.** The chat context assumes one product per chat view. If a conversation can hold
   several, its context set is either all of them — making chat a fan-out context like a pocket — or only the one the
   user addressed, which needs a way to say which that is.
3. **Whether a product should be told why it is in the set.** A product answering from an app or chat context is the
   only thing on screen; the same product answering from a pocket is one of several. Nothing on the wire distinguishes
   these, and a product may reasonably answer differently — most sharply in a chat, where it has a conversation it could
   relate the query to and no signal that it should.
4. **The input syntax.** What textual form produces `App`, `Chat`, and `Pocket` — the scheme, how a modality is
   addressed, how a room or artifact id is written, and how it relates to the `polkadot://<host>.dot/<product>.dot/...`
   links dot.li generates today. This blocks anything printed or shared between hosts.
5. **Ranking within a band.** Products are mutually untrusted and each orders its own candidates. What prevents one from
   returning a plausible candidate for every query to occupy its band? Options: per-product quotas, demotion by
   selection history, or per-product groups instead of a merged list. The context/outside boundary is normative;
   everything inside each band is open.
6. **Whether users need per-product control over queries.** A host-level "never ask this product" control addresses the
   extension's disclosure without a protocol change, and matters more now that a host may ask beyond the screen. Should
   this RFC require it of a host whose extension cap is above zero, rather than leave it to host quality?
7. **What a host may use to choose the outside band.** Selection history, answer rates, and recency are all host-local
   signals, but a host that ranks by them is profiling which products a user finds useful. Whether that is a
   host-quality matter or something the RFC should constrain is unsettled.
8. **Whether a product learns that a static candidate was picked.** A `Custom` candidate reports what the user did
   inside it, so a product that needs to know draws one. `Text`, `RichText`, and `File` report nothing, which means the
   cheapest candidate to produce is the one that tells its product least — and a product wanting analytics has an
   incentive to make every answer custom when it needs no rendering of its own.
9. **Where the attachment declaration belongs.** `query.attachment` sits in the worker manifest, so a product with no
   worker is never offered an attachment even when its app could display one.
10. **Worker stop policy.** Whether a grace period after the last reference is released is host-owned or should be
    specified, and whether a product can ask to be kept alive — a worker with in-flight work of its own has no way to
    say so.
11. **The concrete bounds.** Every recommended value is unvalidated and the attachment cap has none. _D_, _E_, and _R_
    need measurement most: _D_ sets both how live the list feels and how much of a half-typed string leaves the host,
    _E_ sets how far past the screen it goes, and _R_ trades how rich a list can look against how many workers it pins.

## Future Directions and Related Material

Semantically-typed queries — SS58 addresses, extrinsic hashes, referendum numbers, payment URIs — are the next layer,
and `Query` is designed to receive them: each is added to `Query`, claiming input `Text` already carries.

Candidate content grows on the same terms, and `Custom` is the pressure valve: a shape that proves itself as a renderer
tree is a candidate for its own variant, which every host would then draw the same way.

Beyond that: a context the user composes by hand rather than by navigating, which would let someone ask a set of
products picked for the question instead of the set a screen happens to contain; a product-to-product routing path,
which is what would add the `Product` source deliberately left out of `InputSource` today; and candidate freshness,
where a product updates or withdraws a candidate after the round closes.
