import Foundation
import PolkadotUI
import Products
import SwiftUI
import Testing
import TrUAPIHost
@testable import polkadot_app

struct RendererNodeTreeMappingTests {
    let resolver = WidgetDesignTokenResolver()

    @Test
    func textNodeAbsorbsItsStringChildren() {
        let node = RendererNode.text(
            modifiers: [],
            props: TextProps(style: nil, color: nil),
            children: [.string(text: "Loy"), .string(text: "alty")]
        )

        let mapped = node.toWidgetNode(resolver: resolver)

        guard case let .text(props) = mapped?.content else {
            Issue.record("expected a text node, got \(String(describing: mapped?.content))")
            return
        }
        #expect(props.text == "Loyalty")
    }

    @Test
    func textNodeUsesTheColorTokenItNames() {
        let node = RendererNode.text(
            modifiers: [],
            props: TextProps(style: nil, color: .fgError),
            children: [.string(text: "Expired")]
        )

        let mapped = node.toWidgetNode(resolver: resolver)

        guard case let .text(props) = mapped?.content else {
            Issue.record("expected a text node, got \(String(describing: mapped?.content))")
            return
        }
        #expect(props.color.rgba == resolver.color(for: .error).rgba)
        // Guards the assertion above: the resolved values must also tell the
        // named token apart from the default the mapper falls back to.
        #expect(props.color.rgba != resolver.color(for: .textPrimary).rgba)
    }

    @Test
    func textNodeUsesTheTypographyStyleItNames() {
        let node = RendererNode.text(
            modifiers: [],
            props: TextProps(style: .bodySmallRegular, color: nil),
            children: [.string(text: "Fine print")]
        )

        let mapped = node.toWidgetNode(resolver: resolver)

        guard case let .text(props) = mapped?.content else {
            Issue.record("expected a text node, got \(String(describing: mapped?.content))")
            return
        }
        #expect(props.labelStyle.font == PolkadotUI.LabelStyle.caption12Regular().font)
    }

    @Test
    func boxNodeMapsItsChildren() {
        let node = RendererNode.box(
            modifiers: [],
            props: BoxProps(contentAlignment: nil),
            children: [.spacer(modifiers: []), .spacer(modifiers: [])]
        )

        let mapped = node.toWidgetNode(resolver: resolver)

        guard case let .box(_, children) = mapped?.content else {
            Issue.record("expected a box node, got \(String(describing: mapped?.content))")
            return
        }
        #expect(children.count == 2)
    }

    /// A `String` run is absorbed as its parent's text and `Nil` draws nothing,
    /// so neither becomes a child view of its own.
    @Test
    func containerDropsNilAndStringRuns() {
        let node = RendererNode.column(
            modifiers: [],
            props: ColumnProps(horizontalAlignment: nil, verticalArrangement: nil),
            children: [.nil, .string(text: "loose"), .spacer(modifiers: [])]
        )

        let mapped = node.toWidgetNode(resolver: resolver)

        guard case let .column(_, children) = mapped?.content else {
            Issue.record("expected a column node, got \(String(describing: mapped?.content))")
            return
        }
        #expect(children.count == 1)
    }

    @Test
    func rowNodeCarriesItsAlignmentAndArrangement() {
        let node = RendererNode.row(
            modifiers: [],
            props: RowProps(verticalAlignment: .bottom, horizontalArrangement: .spaceBetween),
            children: []
        )

        let mapped = node.toWidgetNode(resolver: resolver)

        guard case let .row(props, _) = mapped?.content else {
            Issue.record("expected a row node, got \(String(describing: mapped?.content))")
            return
        }
        #expect(props.alignment == .bottom)
        #expect(props.arrangement == .spaceBetween)
    }

    @Test
    func buttonNodeCarriesItsActionAndVariant() {
        let node = RendererNode.button(
            modifiers: [],
            props: ButtonProps(
                text: "Stamp",
                variant: .secondary,
                enabled: nil,
                loading: nil,
                clickAction: "stamp"
            ),
            children: []
        )

        let mapped = node.toWidgetNode(resolver: resolver)

        guard case let .button(props) = mapped?.content else {
            Issue.record("expected a button node, got \(String(describing: mapped?.content))")
            return
        }
        #expect(props.text == "Stamp")
        #expect(props.variant == .secondary)
        #expect(props.clickAction == "stamp")
    }

    /// A product that says nothing about a button's state gets one that is
    /// pressable and not spinning, so an omitted field is never read as `false`.
    @Test
    func buttonNodeDefaultsToEnabledAndNotLoading() {
        let node = RendererNode.button(
            modifiers: [],
            props: ButtonProps(text: "Stamp", variant: nil, enabled: nil, loading: nil, clickAction: nil),
            children: []
        )

        let mapped = node.toWidgetNode(resolver: resolver)

        guard case let .button(props) = mapped?.content else {
            Issue.record("expected a button node, got \(String(describing: mapped?.content))")
            return
        }
        #expect(props.isEnabled)
        #expect(!props.isLoading)
    }

    @Test
    func textFieldNodeCarriesItsValueAndChangeAction() {
        let node = RendererNode.textField(
            modifiers: [],
            props: TextFieldProps(
                text: "half",
                placeholder: "amount",
                label: "Amount",
                enabled: false,
                valueChangeAction: "edit"
            )
        )

        let mapped = node.toWidgetNode(resolver: resolver)

        guard case let .textField(props) = mapped?.content else {
            Issue.record("expected a text field node, got \(String(describing: mapped?.content))")
            return
        }
        #expect(props.text == "half")
        #expect(props.placeholder == "amount")
        #expect(props.label == "Amount")
        #expect(props.valueChangeAction == "edit")
        #expect(!props.isEnabled)
    }

    /// A size crosses the wire as an unsigned 64-bit number. Converting one
    /// straight to `CGFloat` hands SwiftUI a value no layout can satisfy, so a
    /// product could take the card's screen down by naming a big enough number.
    /// It is drawn at a bound instead: visibly wrong, still drawing.
    @Test
    func sizeBeyondAnyScreenIsClampedRatherThanRefused() {
        let node = RendererNode.spacer(modifiers: [.width(UInt64.max)])

        let mapped = node.toWidgetNode(resolver: resolver)

        let width = try? #require(mapped?.modifiers.width)
        #expect(width == 100_000)
    }

    /// `fillWidth(false)` is a product saying "do not fill", which must not
    /// read the same as asking to fill.
    @Test
    func fillWidthAppliesOnlyWhenAskedFor() {
        let filling = RendererNode.spacer(modifiers: [.fillWidth(true)])
        let notFilling = RendererNode.spacer(modifiers: [.fillWidth(false)])

        #expect(filling.toWidgetNode(resolver: resolver)?.modifiers.fillWidth == true)
        #expect(notFilling.toWidgetNode(resolver: resolver)?.modifiers.fillWidth == false)
    }

    @Test
    func imageNodeCarriesItsSourceAndFit() {
        let node = RendererNode.image(
            modifiers: [],
            props: ImageProps(source: .archive("faces/logo.png"), fit: .contain)
        )

        let mapped = node.toWidgetNode(resolver: resolver)

        guard case let .image(props) = mapped?.content else {
            Issue.record("expected an image node, got \(String(describing: mapped?.content))")
            return
        }
        #expect(props.source == .archive(path: "faces/logo.png"))
        #expect(props.fit == .contain)
    }

    @Test
    func imageNodeDefaultsToFillWhenNoFitIsNamed() {
        let node = RendererNode.image(
            modifiers: [],
            props: ImageProps(source: .bulletin("bafyreih"), fit: nil)
        )

        let mapped = node.toWidgetNode(resolver: resolver)

        guard case let .image(props) = mapped?.content else {
            Issue.record("expected an image node, got \(String(describing: mapped?.content))")
            return
        }
        #expect(props.source == .bulletin(cid: "bafyreih"))
        #expect(props.fit == .fill)
    }

    @Test
    func effectNodeWrapsItsChildren() {
        let node = RendererNode.effect(
            props: EffectProps(effect: .rainbow),
            children: [.spacer(modifiers: []), .string(text: "absorbed")]
        )

        let mapped = node.toWidgetNode(resolver: resolver)

        guard case let .effect(props, children) = mapped?.content else {
            Issue.record("expected an effect node, got \(String(describing: mapped?.content))")
            return
        }
        #expect(props.effect == .rainbow)
        #expect(children.count == 1)
    }

    @Test
    func blendingModeIsCarried() {
        let node = RendererNode.spacer(modifiers: [.blendingMode(.multiply)])

        let mapped = node.toWidgetNode(resolver: resolver)

        #expect(mapped?.modifiers.blendingMode == .multiply)
    }
}

private extension Color {
    /// SwiftUI `Color` is not reliably `Equatable` for asset-backed colors: two
    /// instances of the same design-system color compare unequal. Tests compare
    /// the concrete values each resolves to instead.
    var rgba: [CGFloat]? {
        let resolved = UIColor(self).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return [red, green, blue, alpha]
    }
}

private extension PolkadotUI.LabelStyle {
    /// `LabelStyle` is not `Equatable` and its fields are internal to PolkadotUI,
    /// so the font it carries is read back through its public attributes.
    var font: UIFont? {
        attributes()[.font] as? UIFont
    }
}
