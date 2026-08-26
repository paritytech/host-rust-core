---
title: "Runtime-aware App executables"
owner: "@replghost"
status: draft
---

# RFC — Runtime-aware App executables

## Summary

This RFC introduces version 2 of the App executable manifest. The new format
makes an App's runtime and runtime requirements explicit.

Web remains the mandatory App runtime and continues to be supported by every
Host that implements the App modality. Version 2 additionally allows a Product
to publish an App compiled for PolkaVM. A PolkaVM App declares the graphics,
device-input, and audio capabilities it requires from the Host.

PolkaVM is an execution environment, not a modality or executable kind.
Framebuffer, Tri2D, and WebGPU Raster are graphics profiles provided to a
PolkaVM App.

## Motivation

The current App manifest describes a static web application:

```ts
type AppManifestV1 = {
  $v: 1;
  kind: "app";
  appVersion: SemVer;
};
```

Its runtime and entrypoint are implicit. The Host assumes that the artifact is
a web directory containing `index.html`.

A PolkaVM App instead contains a program executed in a Host-owned sandbox. The
program does not receive a DOM, native view, filesystem, network connection, or
graphics device directly. It interacts with the Host through bounded,
versioned runtime contracts.

A Host must be able to determine, before launch, which runtime an artifact
requires, where its entrypoint is, which graphics contract it uses, and whether
the current device can satisfy its input, audio, and resource requirements.

Adding these fields to manifest version 1 would be unsafe. An older Host could
ignore them and attempt to launch a PolkaVM artifact as an `index.html` web
application. A new manifest version makes the incompatibility explicit and
fail-closed.

## Detailed Design

### App manifest v2

App executable manifests are stored in the existing `executable` text record
under:

```text
app.<product_id>.<tld>
```

Version 2 is a discriminated union over the runtime:

```ts
type AppManifestV2 =
  | WebAppManifestV2
  | PolkaVmAppManifestV2;

type CommonAppFieldsV2 = {
  $v: 2;
  kind: "app";
  appVersion: SemVer;
};

type WebAppManifestV2 = CommonAppFieldsV2 & {
  runtime: WebRuntime;
};

type PolkaVmAppManifestV2 = CommonAppFieldsV2 & {
  runtime: PolkaVmRuntime;
  capabilities: PolkaVmCapabilities;
};

type WebRuntime = {
  kind: "web";
  entrypoint: string;
};

type PolkaVmRuntime = {
  kind: "polkavm";
  abiVersion: 1;
  entrypoint: string;
};
```

An entrypoint is an archive-relative path. It must be non-empty, must not begin
with `/`, and must not contain `..` path segments. A web entrypoint must
identify an HTML document. A PolkaVM entrypoint must identify a `.polkavm`
program.

The root Product manifest is unchanged and remains independently versioned.

### Web runtime

Web is the mandatory runtime for the App modality.

A Host that implements the App modality must support web App executables. A
Host supporting App manifest version 2 must accept `runtime.kind: "web"`.

App manifest version 1 remains valid and is equivalent to:

```json
{
  "runtime": {
    "kind": "web",
    "entrypoint": "index.html"
  }
}
```

Version 2 does not replace or deprecate the existing web execution model. It
makes the runtime explicit so that web and PolkaVM Apps can use the same
discovery mechanism.

The PolkaVM capability declarations introduced by this RFC do not apply to web
Apps. Web permissions and capabilities continue to be governed by the web
sandbox and existing Host APIs.

### PolkaVM runtime

PolkaVM is an optional App runtime.

A Host that does not implement PolkaVM skips the App executable and reports
that its runtime is unsupported. This does not make the Product malformed or
prevent the Host from using its other executable records.

A PolkaVM App remains `ProductExecutionKind::App` for TruAPI service gating.
Its runtime does not create a new Product identity or permission scope.

Implementing PolkaVM must not reduce or replace the Host's support for web
Apps.

### PolkaVM capabilities

A PolkaVM App declares the capabilities it requires:

```ts
type PolkaVmCapabilities = {
  graphics: GraphicsRequirement;
  deviceInput?: DeviceInputRequirement;
  audio?: AudioRequirement;
};

type GraphicsRequirement = {
  abiVersion: 1;
  profile: "framebuffer" | "tri2d" | "webgpu-raster";
  requiredFeatures: string[];
  requiredLimits?: Record<string, number>;
};

type DeviceInputRequirement = {
  abiVersion: 1;
  requiredFeatures: Array<
    "pointer" | "keyboard" | "touch" | "wheel" |
    "text" | "ime" | "focus"
  >;
};

type AudioRequirement = {
  abiVersion: 1;
  requiredFeatures: string[];
};
```

Graphics is required. Device input and audio are optional and should be omitted
when unused.

The graphics profiles have the following roles:

- `framebuffer` accepts complete packed pixel frames;
- `tri2d` accepts bounded texture updates and clipped indexed triangles through
  a fixed Host rendering contract;
- `webgpu-raster` provides a bounded raster model aligned with WebGPU
  semantics, including retained resources, WGSL shaders, pipelines, render
  passes, and depth attachments.

The profile describes application-visible behavior, not the Host's graphics
backend. A Host may implement a profile over Metal, Vulkan, WebGPU, or another
backend while preserving the specified behavior.

Profile names describe application-visible Host contracts rather than
application architecture or platform graphics APIs. The unqualified name
`webgpu` is reserved for a future contract with a defined level of WebGPU
conformance.

`deviceInput` is distinct from any user-facing Input modality. It describes
operating-system input delivered to a running App. Surface dimensions, scale,
format, and resize generation belong to the graphics contract.

### Capability negotiation

Before starting a PolkaVM App, the Host compares the manifest requirements with
its effective runtime capabilities.

The Host skips the App executable when:

- the runtime or an ABI version is unsupported;
- the graphics profile is unsupported;
- a required feature is unavailable;
- an effective limit is below a declared minimum;
- a required runtime capability cannot be initialized.

Unknown required feature names and limit keys are rejected. Required limit
values must be positive safe integers within the ceilings defined by the
selected profile.

The Host must not silently substitute a different runtime, graphics profile,
or software fallback. Each App executable declares exactly one runtime.

### Embedded manifest

Every version 2 App artifact must contain its executable manifest at:

```text
manifest.json
```

The file must be byte-for-byte identical to the UTF-8 JSON stored in the App
subname's `executable` text record.

A Host installing through dotNS validates the external manifest, fetches the
artifact identified by `contenthash`, and rejects the executable if the
embedded manifest is absent or differs from the external record.

A Host installing an artifact locally or offline uses the embedded manifest as
the executable description.

Publisher tooling should generate the manifest once and use the same bytes for
both locations.

### Artifact identity and versioning

The App subname's `contenthash` remains the executable's immutable identity and
update signal.

`appVersion` remains a publisher-defined, user-visible release label. Hosts
must not use it to determine whether executable bytes changed.

The following versions evolve independently:

- App manifest schema version;
- PolkaVM application ABI version;
- graphics, device-input, and audio ABI versions;
- publisher-defined `appVersion`.

### Runtime contract ownership

This RFC defines runtime discovery and capability negotiation. It does not
define the binary protocol of each runtime capability.

Normative profile specifications, checked decoders, shared constants, and
cross-Host conformance fixtures live in this repository under a Product
Runtime Contracts namespace separate from ordinary TruAPI services.

A platform implementation is not itself normative. A Host may advertise a
profile only when it passes the conformance suite for the declared ABI version.

### Compatibility

Hosts that do not recognize App manifest version 2 skip the App executable and
report an unsupported manifest version. They must not attempt to interpret its
artifact as a version 1 web application.

Hosts supporting version 2 continue to accept version 1 App manifests.

Publisher tooling for version 2 must validate:

- the manifest schema;
- entrypoint paths;
- valid runtime and capability combinations;
- profile-defined feature and limit names;
- the dotNS text-record size budget;
- presence and equality of the embedded manifest;
- required artifact files.

This RFC changes only the App executable. Other executable kinds and
user-facing surfaces remain outside its scope.

## Drawbacks

Hosts and publisher tooling must support two App manifest versions during
migration.

A valid Product may contain an App that cannot run on a particular Host. The
Host must present this as a compatibility limitation rather than as a malformed
or untrusted Product.

The proposal also depends on separately maintained graphics, input, and audio
contracts with conformance coverage across participating Hosts.

Embedding the manifest duplicates information stored in dotNS and introduces
an additional publishing-integrity check.

## Alternatives

### Extend App manifest version 1

Rejected because an older Host could ignore the new fields and attempt to
launch a PolkaVM artifact as web content.

### Define PolkaVM as an executable kind

Rejected because PolkaVM describes how an App executes, not the surface through
which the user encounters it.

### Define Graphics as a modality or executable

Rejected because graphics is a capability of the running App and does not
introduce a separate user-facing surface or lifecycle.

## Unresolved Questions

None.
