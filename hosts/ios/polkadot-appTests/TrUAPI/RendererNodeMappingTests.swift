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
    @Test func anImageKeepsTheSpaceItsModifiersReserve() throws {
        let image = RendererNode.image(
            modifiers: [.width(120), .height(80)],
            props: ImageProps(source: .bulletin(""), fit: nil)
        )

        let widget = try #require(image.toWidgetNode(resolver: resolver))

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
    @Test func effectIsReplacedByItsChildren() throws {
        let effect = RendererNode.effect(
            props: EffectProps(effect: .rainbow),
            children: [
                .text(modifiers: [], props: TextProps(style: nil, color: nil), children: [.string(text: "kept")])
            ]
        )

        // Nested: the parent adopts the children directly, with no node in between.
        let parent = RendererNode.column(
            modifiers: [],
            props: ColumnProps(horizontalAlignment: nil, verticalArrangement: nil),
            children: [effect]
        )
        let widget = try #require(parent.toWidgetNode(resolver: resolver))
        guard case let .column(_, children) = widget.content,
              case let .text(props) = children.first?.content else {
            Issue.record("an effect's children should be adopted by its parent")
            return
        }
        #expect(props.text == "kept")

        // At the root there is one slot, so a lone child fills it directly.
        guard case let .text(rootProps) = try #require(effect.toWidgetNode(resolver: resolver)).content else {
            Issue.record("a root effect with one child should resolve to that child")
            return
        }
        #expect(rootProps.text == "kept")
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
