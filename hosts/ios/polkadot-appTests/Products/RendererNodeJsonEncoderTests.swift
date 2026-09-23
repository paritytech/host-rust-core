import Foundation
import Products
import Testing
import TrUAPIHost
@testable import polkadot_app

/// The encoder exists so a face the host holds survives a relaunch, which is
/// only true if what it writes is what the decoder reads. Every case is checked
/// by round trip rather than against a literal: a literal would encode this
/// host's opinion of the wire, where the decoder is the contract.
struct RendererNodeJsonEncoderTests {
    private let encoder = RendererNodeJsonEncoder()
    private let decoder = RendererNodeJsonDecoder()

    @Test
    func roundTripsTheFaceShippedWithTheApp() async throws {
        let face = try #require(await AssetPinnedPocketCards(tld: "paseo").face(for: PocketCardId(value: "humanity")))

        #expect(try decoder.decode(encoder.encode(face)) == face)
    }

    @Test(arguments: everyNodeKind)
    func roundTripsEveryNodeKind(_ node: RendererNode) throws {
        #expect(try decoder.decode(encoder.encode(node)) == node)
    }

    @Test(arguments: everyModifier)
    func roundTripsEveryModifier(_ modifier: Modifier) throws {
        let node = RendererNode.box(modifiers: [modifier], props: BoxProps(contentAlignment: nil), children: [])

        #expect(try decoder.decode(encoder.encode(node)) == node)
    }

    /// The mapper takes the whole `Size` range and clamps only when it draws, so
    /// a product may legitimately send a size no screen could use. What is
    /// written down still has to read back: a kept face the decoder refuses
    /// costs the card its face at the next cold start.
    @Test(arguments: [Modifier.height(.max), .width(.max), .minWidth(.max), .minHeight(.max)])
    func writesASizeTheDecoderStillReads(_ modifier: Modifier) throws {
        let node = RendererNode.box(modifiers: [modifier], props: BoxProps(contentAlignment: nil), children: [])

        #expect(throws: Never.self) { try decoder.decode(encoder.encode(node)) }
    }

    @Test
    func writesABorderAndPaddingTheDecoderStillReads() throws {
        let node = RendererNode.box(
            modifiers: [
                .padding(Dimensions(top: .max, end: .max, bottom: .max, start: .max)),
                .border(BorderStyle(width: .max, color: .fgError, shape: .rounded(.max)))
            ],
            props: BoxProps(contentAlignment: nil),
            children: []
        )

        #expect(throws: Never.self) { try decoder.decode(encoder.encode(node)) }
    }

    @Test(arguments: RendererWire.blendingModes.values)
    func roundTripsEveryBlendingMode(_ mode: BlendingMode) throws {
        let node = RendererNode.box(
            modifiers: [.blendingMode(mode)],
            props: BoxProps(contentAlignment: nil),
            children: []
        )

        #expect(try decoder.decode(encoder.encode(node)) == node)
    }

    @Test(arguments: RendererWire.contentAlignments.values)
    func roundTripsEveryContentAlignment(_ alignment: ContentAlignment) throws {
        let node = RendererNode.box(
            modifiers: [],
            props: BoxProps(contentAlignment: alignment),
            children: []
        )

        #expect(try decoder.decode(encoder.encode(node)) == node)
    }

    @Test(arguments: RendererWire.colorTokens.values)
    func roundTripsEveryColorToken(_ token: ColorToken) throws {
        let node = RendererNode.text(
            modifiers: [],
            props: TextProps(style: nil, color: token),
            children: [.string(text: "x")]
        )

        #expect(try decoder.decode(encoder.encode(node)) == node)
    }

    @Test(arguments: RendererWire.typographyStyles.values)
    func roundTripsEveryTypographyStyle(_ style: TypographyStyle) throws {
        let node = RendererNode.text(
            modifiers: [],
            props: TextProps(style: style, color: nil),
            children: [.string(text: "x")]
        )

        #expect(try decoder.decode(encoder.encode(node)) == node)
    }

    @Test(arguments: RendererWire.buttonVariants.values)
    func roundTripsEveryButtonVariant(_ variant: ButtonVariant) throws {
        let node = RendererNode.button(
            modifiers: [],
            props: ButtonProps(text: "Go", variant: variant, enabled: true, loading: false, clickAction: "go"),
            children: []
        )

        #expect(try decoder.decode(encoder.encode(node)) == node)
    }

    @Test(arguments: RendererWire.imageFits.values)
    func roundTripsEveryImageFit(_ fit: ImageFit) throws {
        let node = RendererNode.image(
            modifiers: [],
            props: ImageProps(source: .archive("art/badge.png"), fit: fit)
        )

        #expect(try decoder.decode(encoder.encode(node)) == node)
    }

    @Test(arguments: RendererWire.arrangements.values)
    func roundTripsEveryArrangement(_ arrangement: Arrangement) throws {
        let node = RendererNode.column(
            modifiers: [],
            props: ColumnProps(horizontalAlignment: nil, verticalArrangement: arrangement),
            children: []
        )

        #expect(try decoder.decode(encoder.encode(node)) == node)
    }

    /// The alignment enums are the one pair the encoder spells for itself,
    /// because neither type can be named in a signature beside SwiftUI's.
    @Test
    func roundTripsEveryAlignmentTheEncoderSpellsForItself() throws {
        let columns = [
            ColumnProps(horizontalAlignment: .start, verticalArrangement: nil),
            ColumnProps(horizontalAlignment: .center, verticalArrangement: nil),
            ColumnProps(horizontalAlignment: .end, verticalArrangement: nil)
        ]
        let rows = [
            RowProps(verticalAlignment: .top, horizontalArrangement: nil),
            RowProps(verticalAlignment: .center, horizontalArrangement: nil),
            RowProps(verticalAlignment: .bottom, horizontalArrangement: nil)
        ]

        for props in columns {
            let node = RendererNode.column(modifiers: [], props: props, children: [])
            #expect(try decoder.decode(encoder.encode(node)) == node)
        }
        for props in rows {
            let node = RendererNode.row(modifiers: [], props: props, children: [])
            #expect(try decoder.decode(encoder.encode(node)) == node)
        }
    }
}

// MARK: - Fixtures

private let everyNodeKind: [RendererNode] = [
    .nil,
    .string(text: "Loyalty"),
    .box(modifiers: [], props: BoxProps(contentAlignment: .center), children: [.string(text: "in a box")]),
    .column(
        modifiers: [],
        props: ColumnProps(horizontalAlignment: .center, verticalArrangement: .spaceBetween),
        children: [.string(text: "stacked")]
    ),
    .row(
        modifiers: [],
        props: RowProps(verticalAlignment: .bottom, horizontalArrangement: .spaceEvenly),
        children: [.string(text: "beside")]
    ),
    .spacer(modifiers: [.height(8)]),
    .text(
        modifiers: [],
        props: TextProps(style: .headlineLarge, color: .fgPrimary),
        children: [.string(text: "Humanity")]
    ),
    .button(
        modifiers: [],
        props: ButtonProps(text: "Claim", variant: .primary, enabled: true, loading: false, clickAction: "claim"),
        children: []
    ),
    .textField(
        modifiers: [],
        props: TextFieldProps(
            text: "typed",
            placeholder: "name",
            label: "Name",
            enabled: true,
            valueChangeAction: "changed"
        )
    ),
    .image(modifiers: [], props: ImageProps(source: .bulletin("bafyimage"), fit: .cover)),
    .effect(props: EffectProps(effect: .rainbow), children: [.string(text: "shiny")])
]

private let everyModifier: [Modifier] = [
    .margin(Dimensions(top: 1, end: 2, bottom: 3, start: 4)),
    .padding(Dimensions(top: 5, end: 6, bottom: nil, start: nil)),
    .background(Background(color: .bgSurfaceMain, shape: .rounded(12))),
    .background(Background(color: .bgSurfaceNested, shape: .circle)),
    .background(Background(color: .bgSurfaceContainer, shape: .square)),
    .background(Background(color: .bgSurfaceContainer, shape: nil)),
    .border(BorderStyle(width: 2, color: .fgError, shape: .rounded(4))),
    .border(BorderStyle(width: 1, color: .fgWarning, shape: nil)),
    .height(48),
    .width(96),
    .minWidth(10),
    .minHeight(20),
    .fillWidth(true),
    .fillHeight(false),
    .opacity(200),
    .blendingMode(.multiply)
]
