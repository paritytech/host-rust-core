import Foundation
import Testing
import TrUAPIHost
@testable import polkadot_app

struct RendererNodeJsonDecoderTests {
    let decoder = RendererNodeJsonDecoder()

    /// The smallest face that draws, as the card-authoring guide documents it.
    @Test
    func decodesTheSmallestFaceThatDraws() throws {
        let json = """
        {
          "tag": "Column",
          "value": {
            "modifiers": [{ "tag": "Padding", "value": { "top": 16, "end": 16 } }],
            "props": {},
            "children": [
              {
                "tag": "Text",
                "value": {
                  "modifiers": [],
                  "props": { "style": "TitleMediumRegular", "color": "FgPrimary" },
                  "children": [{ "tag": "String", "value": { "text": "Loyalty" } }]
                }
              }
            ]
          }
        }
        """

        let node = try decoder.decode(json)

        #expect(node == .column(
            modifiers: [.padding(Dimensions(top: 16, end: 16, bottom: nil, start: nil))],
            props: ColumnProps(horizontalAlignment: nil, verticalArrangement: nil),
            children: [
                .text(
                    modifiers: [],
                    props: TextProps(style: .titleMediumRegular, color: .fgPrimary),
                    children: [.string(text: "Loyalty")]
                )
            ]
        ))
    }

    /// A unit variant carries no `value` at all.
    @Test
    func decodesUnitVariantsWithoutAValue() throws {
        #expect(try decoder.decode(#"{ "tag": "Nil" }"#) == .nil)
    }

    @Test
    func decodesAnImageSourceAndFit() throws {
        let json = """
        {
          "tag": "Image",
          "value": {
            "modifiers": [],
            "props": { "source": { "tag": "Archive", "value": "faces/logo.png" }, "fit": "Contain" }
          }
        }
        """

        let node = try decoder.decode(json)

        #expect(node == .image(
            modifiers: [],
            props: ImageProps(source: .archive("faces/logo.png"), fit: .contain)
        ))
    }

    /// Enum names arrive PascalCase and have to reach the right case even when
    /// the Swift spelling differs, which `BgSurfaceMain` is the awkward one for.
    @Test
    func decodesPascalCaseEnumNames() throws {
        let json = """
        {
          "tag": "Spacer",
          "value": {
            "modifiers": [{ "tag": "Background", "value": { "color": "BgSurfaceMain" } }]
          }
        }
        """

        let node = try decoder.decode(json)

        #expect(node == .spacer(modifiers: [.background(Background(color: .bgSurfaceMain, shape: nil))]))
    }

    /// A face is product-authored and arrives before the user has approved
    /// anything, so a tree that would exhaust the stack is refused outright.
    @Test
    func refusesATreeDeeperThanTheLimit() {
        var json = #"{ "tag": "Nil" }"#
        for _ in 0 ..< 40 {
            json = #"{ "tag": "Box", "value": { "modifiers": [], "props": {}, "children": [\#(json)] } }"#
        }

        #expect(throws: (any Error).self) {
            try decoder.decode(json)
        }
    }

    @Test
    func refusesAnUnknownNodeTag() {
        #expect(throws: (any Error).self) {
            try decoder.decode(#"{ "tag": "Barcode", "value": {} }"#)
        }
    }

    /// Kept identical to the bound the Android host applies, so a face one host
    /// accepts is not silently refused by the other.
    @Test
    func refusesASizeBeyondTheSharedBound() {
        let json = #"{ "tag": "Spacer", "value": { "modifiers": [{ "tag": "Width", "value": 2147483648 }] } }"#

        #expect(throws: (any Error).self) {
            try decoder.decode(json)
        }
    }

    @Test
    func refusesANegativeSize() {
        let json = #"{ "tag": "Spacer", "value": { "modifiers": [{ "tag": "Padding", "value": { "top": -1, "end": 0 } }] } }"#

        #expect(throws: (any Error).self) {
            try decoder.decode(json)
        }
    }

    /// Anything outside a byte would wrap into a different opacity, with 256
    /// landing on fully transparent.
    @Test
    func refusesAnOpacityOutsideAByte() {
        let json = #"{ "tag": "Spacer", "value": { "modifiers": [{ "tag": "Opacity", "value": 256 }] } }"#

        #expect(throws: (any Error).self) {
            try decoder.decode(json)
        }
    }
}
