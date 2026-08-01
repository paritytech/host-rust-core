# Modalities

Source: [Google Doc](https://docs.google.com/document/d/1YX-OVNqRNJ-9qDCYHGwZstW_4NxnciqQ6UvG4_kO0x0/edit)
Owner: Torsten Stüber · Classification: Internal · Last modified: 2026-07-31

In this document I propose a rough sketch of a framework for how a product defines and implements modalities. This applies to

* SPA Modality
* Input Modality
* Pocket Modality
* Funding Modality

Extension modalities are more generic and out of scope for the purposes of this document.

### Manifest

Each product defines its modalities in the product manifest. I propose a new entry in the manifest called `"modalities"`. Its value is a JSON object with the following members, each of them optional:

* `"spa"`
* `"pocket"`
* `"input"`
* `"funding"`
* (and other entries for new modalities we introduce or support later)

A product only declares modalities it supports and provides.

The value for each declared modality is a JSON object with entries `"views"` and `"api"`. The structure of the values of `"views"` and `"api"` depends on the modality type (see below). If the modality type does not define any `"views"` or `"api"`, then the respective field can be left out.

The `"views"` of the modality define different views the modality has to provide. The shape of its value looks as follows:

* for `"spa"`: `{ "spa": <ViewDefinition> }`
* for `"pocket"`: `{ "card": <ViewDefinition>, "expanded": <ViewDefinition> }`
* for `"input"`: empty object
* for `"funding"`: empty object

The `ViewDefinition` refers to a webapp bundle (either via CID or in the product bundle retrieved from BC), similar to an SPA modality.

* **Question**: which option makes more sense?
* **Question**: should it also contain the view size? I think that products should define their view in a responsive way (adapt to any size) and the host decides the size of the view (i.e., to standardize the card size for pocket)

The `"api"` definitions of a modality are entry points into logic the modality provides. The shape of its value looks as follows:

* for `"spa"`: empty object
* for `"pocket"`: empty object
* for `"input"`: `{ "acceptsInput": <ApiDefinition>, "search": <ApiDefinition> }`
* for `"funding"`: `{ "acceptFunding": <ApiDefinition> }`

The `ApiDefinition` is a name of the worker JS executable. This executable needs to be provided as part of the product bundle whenever the product defines a modality that has a nonempty `"api"` definition.

The host will call the api function of defined modalities whenever it needs to execute certain actions, for example when it provides the input or funding UI to the user. When and how this happens is out of scope for this document.

### Sandbox

The JS code of each view and the worker JS code need to be executed within the Trinity Sandbox and have to use the TrUAPI.

### Shared Data

**Open Questions:**

* Is local storage shared across all modalities of a product?
* Are product accounts shared across all modalities of a product?

I propose to answer both questions with "yes" because whenever the worker JS code calls a TrUAPI function, it is not immediately clear what modality entry point led to the execution of this TrUAPI function and therefore it is not obvious how the TrUAPI can easily distinguish between modalities.
