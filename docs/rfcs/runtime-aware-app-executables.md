---
title: "Runtime-aware App executables"
owner: "@replghost"
status: draft
---

# RFC — Runtime-aware App executables

## Summary

This RFC introduces version 2 of the App executable manifest. It allows an App
to declare whether it runs as a web application or as a PolkaVM program.

Web remains the mandatory App runtime. PolkaVM is an optional runtime that a
Host may additionally support. A PolkaVM App declares the versioned graphics
and other runtime capabilities it requires.

PolkaVM is a runtime, not a new modality or executable kind. A PolkaVM App
retains the identity, lifecycle, and TruAPI access of an App.

## Motivation

The version 1 App manifest assumes that every App is a web directory containing
`index.html`:

```json
{
  "$v": 1,
  "kind": "app",
  "appVersion": [1, 0, 0]
}
```

This is insufficient for an App distributed as a PolkaVM program. Before
launch, a Host must know which runtime the artifact requires, where its
entrypoint is, and which Host capabilities are needed to present and operate
it.

Adding these fields to version 1 would be unsafe. An older Host could ignore
them and attempt to launch a PolkaVM artifact as web content. Version 2 makes
the distinction explicit and fail-closed.

## Detailed Design

### Manifest location and versioning

App manifests remain stored in the `executable` text record under:

```text
app.<product_id>.<tld>
```

The root Product manifest is unchanged. Manifest versions apply to individual
records, so a version 1 root manifest may reference a version 2 App executable.

Each version 2 App declares exactly one runtime.

### Web runtime

A version 2 web App declares its entrypoint explicitly:

```json
{
  "$v": 2,
  "kind": "app",
  "appVersion": [1, 4, 0],
  "runtime": {
    "kind": "web",
    "entrypoint": "index.html"
  }
}
```

Web is the mandatory runtime for Hosts implementing the App modality. App
manifest version 1 remains valid and continues to imply a web runtime with
`index.html` as its entrypoint.

Version 2 does not replace or deprecate the existing web execution model. It
makes the runtime explicit so that web and PolkaVM Apps can use the same
discovery mechanism.

### PolkaVM runtime

A PolkaVM App declares its program, application ABI, and required Host
capabilities:

```json
{
  "$v": 2,
  "kind": "app",
  "appVersion": [0, 1, 0],
  "runtime": {
    "kind": "polkavm",
    "abiVersion": 1,
    "entrypoint": "app.polkavm"
  },
  "capabilities": {
    "graphics": {
      "abiVersion": 1,
      "profile": "tri2d"
    },
    "deviceInput": {
      "abiVersion": 1
    },
    "audio": {
      "abiVersion": 1
    }
  }
}
```

PolkaVM support is optional. A Host that does not implement the PolkaVM runtime
skips the App executable and reports it as unsupported. This does not make the
Product malformed or affect its other executable records.

A PolkaVM App must declare a graphics capability. Device input and audio are
optional and should be omitted when unused.

Runtime entrypoints are relative to the executable artifact. A web entrypoint
identifies an HTML document. A PolkaVM entrypoint identifies a `.polkavm`
program.

A PolkaVM App remains `ProductExecutionKind::App`. Its runtime does not create
a new Product identity, executable kind, or permission scope.

### Graphics profiles

Graphics ABI version 1 initially identifies three profiles:

- `framebuffer` for complete packed pixel frames;
- `tri2d` for bounded textures and clipped indexed triangles;
- `webgpu-raster` for a bounded raster contract aligned with WebGPU semantics.

These profiles describe application-visible behavior, not the graphics backend
used by a particular Host. Different Hosts may implement the same profile
through different platform facilities.

The operations, wire formats, feature vocabularies, limits, error behavior,
and conformance requirements of each profile are defined in separate
runtime-profile specifications.

The unqualified name `webgpu` is reserved for a future contract with a defined
level of WebGPU conformance.

Device input and audio follow the same versioning model: the App manifest
declares the required ABI version, while a separate runtime specification
defines its operations and behavior.

### Host behavior

Before launch, the Host checks whether it supports:

- the declared runtime and runtime ABI;
- the declared graphics profile and ABI;
- the ABI versions of any other declared capabilities.

If a requirement is unsupported, the Host skips that App executable and
reports it as incompatible. The Product and its other executable records
remain valid.

The Host must not silently substitute another runtime or graphics profile. It
either launches the declared runtime or reports the App as unsupported.

A Host is not required to implement PolkaVM or every graphics profile.
Implementing PolkaVM must not reduce or replace its support for web Apps.

### Artifact identity

The App subname's `contenthash` remains the executable artifact's immutable
identity and update signal.

`appVersion` remains a publisher-defined, user-visible release label. Hosts
must not use it to determine whether executable bytes changed.

The manifest schema, PolkaVM application ABI, runtime-capability ABIs, and
`appVersion` evolve independently.

### Compatibility

A Host that does not recognize App manifest version 2 skips the App executable.
It must not interpret its artifact as a version 1 web application.

A Host supporting version 2 continues to accept version 1 App manifests.

This RFC changes only the App executable. Other executable kinds and
user-facing surfaces are outside its scope.

## Drawbacks

Hosts and publisher tooling must support two App manifest versions.

A valid Product may contain an App that is unavailable on a particular Host.
The Host must present this as a compatibility limitation rather than as a
malformed or untrusted Product.

The runtime capabilities named by this RFC require separate specifications and
cross-Host conformance tests.

## Alternatives

### Extend App manifest version 1

Rejected because older Hosts could ignore the new fields and attempt to launch
a PolkaVM artifact as web content.

### Define PolkaVM as an executable kind

Rejected because PolkaVM describes how an App executes, not how the Product is
presented to the user.

### Define Graphics as a modality

Rejected because graphics is a capability of a running App and does not
introduce a separate user-facing surface.

## Unresolved Questions

The detailed graphics, device-input, and audio contracts will be proposed
separately.
