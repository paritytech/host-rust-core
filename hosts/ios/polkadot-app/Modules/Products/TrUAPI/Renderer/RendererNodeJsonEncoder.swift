import Foundation
import TrUAPIHost

/// Writes a renderer tree back into the shape ``RendererNodeJsonDecoder`` reads,
/// so a face the host holds can be kept and read again after a relaunch.
///
/// Enum spellings come from ``RendererWire``, the same table the decoder reads,
/// so the two directions cannot drift apart.
struct RendererNodeJsonEncoder {
    func encode(_ node: RendererNode) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: object(node),
            options: [.fragmentsAllowed, .sortedKeys]
        )
        guard let json = String(bytes: data, encoding: .utf8) else {
            throw RendererNodeJsonError.notUtf8
        }
        return json
    }
}

// MARK: - Nodes

private extension RendererNodeJsonEncoder {
    // swiftlint:disable:next cyclomatic_complexity
    func object(_ node: RendererNode) -> [String: Any] {
        switch node {
        case .nil:
            ["tag": "Nil"]
        case let .string(text):
            tagged("String", ["text": text])
        case let .box(modifiers, props, children):
            container("Box", modifiers, children, ["contentAlignment": name(props.contentAlignment)])
        case let .column(modifiers, props, children):
            column(modifiers, props, children)
        case let .row(modifiers, props, children):
            row(modifiers, props, children)
        case let .spacer(modifiers):
            tagged("Spacer", ["modifiers": modifiers.map(modifier)])
        case let .text(modifiers, props, children):
            container("Text", modifiers, children, [
                "style": name(props.style),
                "color": name(props.color)
            ])
        case let .button(modifiers, props, children):
            container("Button", modifiers, children, [
                "text": props.text,
                "variant": name(props.variant),
                "enabled": props.enabled,
                "loading": props.loading,
                "clickAction": props.clickAction
            ])
        case let .textField(modifiers, props):
            container("TextField", modifiers, [], [
                "text": props.text,
                "placeholder": props.placeholder,
                "label": props.label,
                "enabled": props.enabled,
                "valueChangeAction": props.valueChangeAction
            ])
        case let .image(modifiers, props):
            container("Image", modifiers, [], [
                "source": source(props.source),
                "fit": name(props.fit)
            ])
        case let .effect(props, children):
            tagged("Effect", [
                "props": ["effect": name(props.effect)],
                "children": children.map(object)
            ])
        }
    }

    // The alignment is read off the props rather than passed: those two enums
    // share their names with SwiftUI's, and neither can be written in a
    // signature here — the same reason the decoder builds its props whole.
    func column(_ modifiers: [Modifier], _ props: ColumnProps, _ children: [RendererNode]) -> [String: Any] {
        let horizontal: String? =
            switch props.horizontalAlignment {
            case .start: "Start"
            case .center: "Center"
            case .end: "End"
            case nil: nil
            }

        return container("Column", modifiers, children, [
            "horizontalAlignment": horizontal,
            "verticalArrangement": name(props.verticalArrangement)
        ])
    }

    func row(_ modifiers: [Modifier], _ props: RowProps, _ children: [RendererNode]) -> [String: Any] {
        let vertical: String? =
            switch props.verticalAlignment {
            case .top: "Top"
            case .center: "Center"
            case .bottom: "Bottom"
            case nil: nil
            }

        return container("Row", modifiers, children, [
            "verticalAlignment": vertical,
            "horizontalArrangement": name(props.horizontalArrangement)
        ])
    }

    func tagged(_ tag: String, _ value: [String: Any]) -> [String: Any] {
        ["tag": tag, "value": value]
    }

    /// A tag whose value is an enum spelling. `RendererWire` is spelled out by
    /// hand, so a case added to the bindings has no name here until someone
    /// adds it; leaving the value out makes the decoder refuse that face, which
    /// costs the card its kept face rather than writing a modifier it would
    /// read back as something else.
    func spelled(_ tag: String, _ value: String?) -> [String: Any] {
        let fields: [String: Any?] = ["tag": tag, "value": value]
        return fields.compactMapValues { $0 }
    }

    func container(
        _ tag: String,
        _ modifiers: [Modifier],
        _ children: [RendererNode],
        _ props: [String: Any?]
    ) -> [String: Any] {
        tagged(tag, [
            "modifiers": modifiers.map(modifier),
            "props": props.compactMapValues { $0 },
            "children": children.map(object)
        ])
    }
}

// MARK: - Modifiers

private extension RendererNodeJsonEncoder {
    // swiftlint:disable:next cyclomatic_complexity
    func modifier(_ modifier: Modifier) -> [String: Any] {
        switch modifier {
        case let .margin(dimensions): tagged("Margin", self.dimensions(dimensions))
        case let .padding(dimensions): tagged("Padding", self.dimensions(dimensions))
        case let .background(background): tagged("Background", self.background(background))
        case let .border(style): tagged("Border", borderStyle(style))
        case let .height(size): ["tag": "Height", "value": readable(size)]
        case let .width(size): ["tag": "Width", "value": readable(size)]
        case let .minWidth(size): ["tag": "MinWidth", "value": readable(size)]
        case let .minHeight(size): ["tag": "MinHeight", "value": readable(size)]
        case let .fillWidth(fills): ["tag": "FillWidth", "value": fills]
        case let .fillHeight(fills): ["tag": "FillHeight", "value": fills]
        case let .opacity(opacity): ["tag": "Opacity", "value": opacity]
        case let .blendingMode(mode): spelled("BlendingMode", name(mode))
        }
    }

    func dimensions(_ dimensions: Dimensions) -> [String: Any] {
        let values: [String: Any?] = [
            "top": readable(dimensions.top),
            "end": readable(dimensions.end),
            "bottom": dimensions.bottom.map(readable),
            "start": dimensions.start.map(readable)
        ]
        return values.compactMapValues { $0 }
    }

    /// A size no larger than the decoder will read back. The renderer clamps
    /// every size before it draws, so a face kept this way draws exactly as the
    /// product meant it to — where one written past the bound would be refused
    /// at the next cold start, taking the card's kept face with it.
    func readable(_ size: Size) -> Size {
        min(size, RendererWire.maxSize)
    }

    // The shape is read off its enclosing value rather than passed: `Shape`
    // names both a SwiftUI protocol and a core enum, and neither spelling
    // reaches the enum, so it cannot be written in a signature.
    func background(_ background: Background) -> [String: Any] {
        let shape: [String: Any]? =
            switch background.shape {
            case .none: nil
            case let .rounded(radius): ["tag": "Rounded", "value": readable(radius)]
            case .circle: ["tag": "Circle"]
            case .square: ["tag": "Square"]
            }

        let values: [String: Any?] = ["color": name(background.color), "shape": shape]
        return values.compactMapValues { $0 }
    }

    func borderStyle(_ style: BorderStyle) -> [String: Any] {
        let shape: [String: Any]? =
            switch style.shape {
            case .none: nil
            case let .rounded(radius): ["tag": "Rounded", "value": readable(radius)]
            case .circle: ["tag": "Circle"]
            case .square: ["tag": "Square"]
            }

        let values: [String: Any?] = [
            "width": readable(style.width),
            "color": name(style.color),
            "shape": shape
        ]
        return values.compactMapValues { $0 }
    }

    func source(_ source: ImageSource) -> [String: Any] {
        switch source {
        case let .bulletin(cid): ["tag": "Bulletin", "value": cid]
        case let .archive(path): ["tag": "Archive", "value": path]
        }
    }
}

// MARK: - Enums

private extension RendererNodeJsonEncoder {
    func name(_ value: ContentAlignment?) -> String? { named(value, RendererWire.contentAlignments) }
    func name(_ value: Arrangement?) -> String? { named(value, RendererWire.arrangements) }
    func name(_ value: TypographyStyle?) -> String? { named(value, RendererWire.typographyStyles) }
    func name(_ value: ColorToken?) -> String? { named(value, RendererWire.colorTokens) }
    func name(_ value: ButtonVariant?) -> String? { named(value, RendererWire.buttonVariants) }
    func name(_ value: ImageFit?) -> String? { named(value, RendererWire.imageFits) }
    func name(_ value: Effect) -> String? { named(value, RendererWire.effects) }
    func name(_ value: BlendingMode) -> String? { named(value, RendererWire.blendingModes) }

    func named<T: Hashable>(_ value: T?, _ cases: [String: T]) -> String? {
        value.flatMap { RendererWire.name(of: $0, in: cases) }
    }
}
