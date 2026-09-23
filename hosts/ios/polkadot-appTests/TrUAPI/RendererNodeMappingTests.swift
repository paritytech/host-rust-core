import Foundation
import Products
import SwiftUI
import Testing
import TrUAPIHost
@testable import polkadot_app

@Suite("RendererNode mapping")
struct RendererNodeMappingTests {
    private let resolver = StubWidgetDesignTokenResolver()

    private func paddingOfBox(_ dimensions: Dimensions) throws -> EdgeInsets {
        let node = RendererNode.box(
            modifiers: [.padding(dimensions)],
            props: BoxProps(contentAlignment: nil),
            children: []
        )
        let widget = try #require(node.toWidgetNode(resolver: resolver))
        return widget.modifiers.padding
    }

    private func opacityOfBox(_ modifiers: [Modifier]) throws -> CGFloat? {
        let node = RendererNode.box(
            modifiers: modifiers,
            props: BoxProps(contentAlignment: nil),
            children: []
        )
        let widget = try #require(node.toWidgetNode(resolver: resolver))
        return widget.modifiers.opacity
    }

    @Test func opacityMapsTheCoreRangeOntoSwiftUI() throws {
        #expect(try opacityOfBox([.opacity(0)]) == 0)
        #expect(try opacityOfBox([.opacity(255)]) == 1)
        #expect(try opacityOfBox([.opacity(128)]) == CGFloat(128) / 255)
    }

    /// No modifier is fully opaque, and the view applies `?? 1` to say so.
    @Test func noOpacityModifierLeavesItUnset() throws {
        #expect(try opacityOfBox([]) == nil)
    }

    @Test func everyEdgeIsExplicit() throws {
        let padding = try paddingOfBox(Dimensions(top: 4, end: 8, bottom: 12, start: 16))

        #expect(padding.top == 4)
        #expect(padding.trailing == 8)
        #expect(padding.bottom == 12)
        #expect(padding.leading == 16)
    }

    @Test func bottomDefaultsToTopAndStartToEnd() throws {
        let padding = try paddingOfBox(Dimensions(top: 4, end: 8, bottom: nil, start: nil))

        #expect(padding.top == 4)
        #expect(padding.trailing == 8)
        #expect(padding.bottom == 4)
        #expect(padding.leading == 8)
    }

    @Test func uniformDimensionsAreUnchanged() throws {
        let padding = try paddingOfBox(Dimensions(top: 16, end: 16, bottom: 16, start: 16))

        #expect(padding.top == 16)
        #expect(padding.leading == 16)
        #expect(padding.bottom == 16)
        #expect(padding.trailing == 16)
    }

    /// The picture cannot be drawn, but the space it reserved has to survive,
    /// or everything laid out around it moves.
    @Test func anImageDrawsItsSourceAndKeepsItsSpace() throws {
        let image = RendererNode.image(
            modifiers: [.width(120), .height(80)],
            props: ImageProps(source: .bulletin("bafyimage"), fit: nil)
        )

        let widget = try #require(image.toWidgetNode(resolver: resolver))

        guard case let .image(props) = widget.content else {
            Issue.record("an image node should draw its source")
            return
        }
        #expect(props.source == .bulletin(cid: "bafyimage"))
        #expect(widget.modifiers.width == 120)
        #expect(widget.modifiers.height == 80)
    }

    /// The renderer gained a square shape; the resolver is defined over
    /// `ScaleShape`, which spells one as a zero-radius rounded rect. Asserted
    /// on what the resolver was handed: the stub ignores its argument, so a
    /// wrong translation would still produce a border.
    @Test func squareTranslatesToAZeroRadiusRoundedRect() throws {
        let recorder = ShapeRecordingResolver()
        let node = RendererNode.box(
            modifiers: [.border(BorderStyle(width: 2, color: .fgPrimary, shape: .square))],
            props: BoxProps(contentAlignment: nil),
            children: []
        )

        _ = try #require(node.toWidgetNode(resolver: recorder))

        guard case let .rounded(radius) = try #require(recorder.shapes.first) else {
            Issue.record("a square must translate to a rounded rect, not a circle")
            return
        }
        #expect(radius == 0)
    }

    /// An effect's children take its place, rather than gaining a container.
    @Test func anEffectKeepsItsChildrenAndItsOwnNode() throws {
        let effect = RendererNode.effect(
            props: EffectProps(effect: .rainbow),
            children: [
                .text(modifiers: [], props: TextProps(style: nil, color: nil), children: [.string(text: "kept")])
            ]
        )

        guard case let .effect(props, children) = try #require(effect.toWidgetNode(resolver: resolver)).content,
              case let .text(textProps) = children.first?.content
        else {
            Issue.record("an effect should keep both its own node and its children")
            return
        }
        #expect(props.effect == .rainbow)
        #expect(textProps.text == "kept")
    }
}

/// Records the shapes the mapping resolves, so a token translation can be
/// asserted instead of merely exercised.
private final class ShapeRecordingResolver: WidgetDesignTokenResolving {
    private(set) var shapes: [ScaleShape] = []

    func color(for _: ScaleColorToken) -> Color { .clear }
    func font(for _: ScaleTypographyStyle) -> Font { .body }
    func labelStyle(for _: ScaleTypographyStyle) -> (font: Font, lineSpacing: CGFloat) { (.body, 0) }
    func cornerRadius(for _: ScaleShape) -> CGFloat { 0 }
    func buttonStyle(for _: ScaleButtonVariant) -> (background: Color, foreground: Color) { (.clear, .clear) }

    func shape(for scaleShape: ScaleShape) -> AnyShape {
        shapes.append(scaleShape)
        return AnyShape(Rectangle())
    }
}
