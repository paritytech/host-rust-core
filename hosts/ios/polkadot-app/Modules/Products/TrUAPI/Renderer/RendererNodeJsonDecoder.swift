import Foundation
import TrUAPIHost

enum RendererNodeJsonError: Error, CustomStringConvertible {
    case notAnObject
    case missingField(String)
    case unknownNode(String)
    case unknownModifier(String)
    case unknownImageSource(String)
    case unknownShape(String)
    case unknownValue(String)
    case treeTooDeep(Int)
    case sizeOutOfRange(String)
    case opacityOutOfRange(String)

    var description: String {
        switch self {
        case .notAnObject: "renderer node is not an object"
        case let .missingField(key): "renderer node missing '\(key)'"
        case let .unknownNode(tag): "unknown renderer node '\(tag)'"
        case let .unknownModifier(tag): "unknown renderer modifier '\(tag)'"
        case let .unknownImageSource(tag): "unknown image source '\(tag)'"
        case let .unknownShape(tag): "unknown renderer shape '\(tag)'"
        case let .unknownValue(value): "unknown renderer value '\(value)'"
        case let .treeTooDeep(limit): "renderer tree deeper than \(limit) levels"
        case let .sizeOutOfRange(value): "renderer size out of range: \(value)"
        case let .opacityOutOfRange(value): "renderer opacity out of range: \(value)"
        }
    }
}

private enum Limit {
    static let depth = 32
    static let size = Double(RendererWire.maxSize)
}

private func jsonObject(_ element: Any?) throws -> [String: Any] {
    guard let object = element as? [String: Any] else { throw RendererNodeJsonError.notAnObject }
    return object
}

/// Reads a renderer tree written in the generated TypeScript shape
/// (`{ tag, value }` per variant, PascalCase enum names) into the node the core
/// streams, so a static preview and a live face go through one mapping.
///
/// The input is product-authored and reaches the host before the user has
/// approved anything, so depth, sizes and opacity are bounded here.
struct RendererNodeJsonDecoder {
    func decode(_ json: String) throws -> RendererNode {
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed])
        return try node(from: parsed, depth: 1)
    }
}

// MARK: - Nodes

private extension RendererNodeJsonDecoder {
    func node(from element: Any, depth: Int) throws -> RendererNode {
        guard depth <= Limit.depth else { throw RendererNodeJsonError.treeTooDeep(Limit.depth) }
        let object = try jsonObject(element)
        let tag = try object.string("tag")
        // A unit variant carries no `value`; a field read off an absent one
        // then fails as missing rather than as a shape error.
        let value = object.object("value") ?? [:]
        let props = value.object("props") ?? [:]

        switch tag {
        case "Nil":
            return .nil
        case "String":
            return try .string(text: value.string("text"))
        case "Box":
            return try .box(
                modifiers: value.modifiers(),
                props: BoxProps(contentAlignment: props.contentAlignment("contentAlignment")),
                children: children(of: value, depth: depth)
            )
        case "Column":
            return try .column(
                modifiers: value.modifiers(),
                props: props.columnProps(),
                children: children(of: value, depth: depth)
            )
        case "Row":
            return try .row(
                modifiers: value.modifiers(),
                props: props.rowProps(),
                children: children(of: value, depth: depth)
            )
        case "Spacer":
            return try .spacer(modifiers: value.modifiers())
        case "Text":
            return try .text(
                modifiers: value.modifiers(),
                props: TextProps(style: props.typographyStyle("style"), color: props.colorToken("color")),
                children: children(of: value, depth: depth)
            )
        case "Button":
            return try .button(
                modifiers: value.modifiers(),
                props: ButtonProps(
                    text: props.string("text"),
                    variant: props.buttonVariant("variant"),
                    enabled: props.boolean("enabled"),
                    loading: props.boolean("loading"),
                    clickAction: props.stringOrNil("clickAction")
                ),
                children: children(of: value, depth: depth)
            )
        case "TextField":
            return try .textField(
                modifiers: value.modifiers(),
                props: TextFieldProps(
                    text: props.string("text"),
                    placeholder: props.stringOrNil("placeholder"),
                    label: props.stringOrNil("label"),
                    enabled: props.boolean("enabled"),
                    valueChangeAction: props.stringOrNil("valueChangeAction")
                )
            )
        case "Image":
            return try .image(
                modifiers: value.modifiers(),
                props: ImageProps(source: props.imageSource("source"), fit: props.imageFit("fit"))
            )
        case "Effect":
            return try .effect(
                props: EffectProps(effect: props.effect("effect")),
                children: children(of: value, depth: depth)
            )
        default:
            throw RendererNodeJsonError.unknownNode(tag)
        }
    }

    func children(of value: [String: Any], depth: Int) throws -> [RendererNode] {
        try value.array("children").map { try node(from: $0, depth: depth + 1) }
    }
}

// MARK: - Modifiers

private extension [String: Any] {
    func modifiers() throws -> [Modifier] {
        try array("modifiers").map { try Self.modifier(from: $0) }
    }

    static func modifier(from element: Any) throws -> Modifier {
        let object = try jsonObject(element)
        let value = object["value"]

        switch try object.string("tag") {
        case "Margin": return try .margin(jsonObject(value).dimensions())
        case "Padding": return try .padding(jsonObject(value).dimensions())
        case "Background": return try .background(jsonObject(value).background())
        case "Border": return try .border(jsonObject(value).borderStyle())
        case "Height": return try .height(size(from: value))
        case "Width": return try .width(size(from: value))
        case "MinWidth": return try .minWidth(size(from: value))
        case "MinHeight": return try .minHeight(size(from: value))
        case "FillWidth": return try .fillWidth(boolean(from: value))
        case "FillHeight": return try .fillHeight(boolean(from: value))
        case "Opacity": return try .opacity(opacity(from: value))
        case "BlendingMode": return try .blendingMode(blendingMode(from: value))
        case let tag: throw RendererNodeJsonError.unknownModifier(tag)
        }
    }

    func dimensions() throws -> Dimensions {
        try Dimensions(top: size("top"), end: size("end"), bottom: sizeOrNil("bottom"), start: sizeOrNil("start"))
    }

    // The shape is built into its enclosing value rather than returned: `Shape`
    // names both a SwiftUI protocol and a core enum, and neither spelling
    // reaches the enum, so the case is only ever written where the initializer
    // parameter infers it.
    func background() throws -> Background {
        let color = try requiredColorToken("color")
        guard let shape = self["shape"], !(shape is NSNull) else { return Background(color: color, shape: nil) }
        let object = try jsonObject(shape)

        switch try object.string("tag") {
        case "Rounded": return try Background(color: color, shape: .rounded(Self.size(from: object["value"])))
        case "Circle": return Background(color: color, shape: .circle)
        case "Square": return Background(color: color, shape: .square)
        case let tag: throw RendererNodeJsonError.unknownShape(tag)
        }
    }

    func borderStyle() throws -> BorderStyle {
        let width = try size("width")
        let color = try requiredColorToken("color")
        guard let shape = self["shape"], !(shape is NSNull) else {
            return BorderStyle(width: width, color: color, shape: nil)
        }
        let object = try jsonObject(shape)

        switch try object.string("tag") {
        case "Rounded":
            return try BorderStyle(width: width, color: color, shape: .rounded(Self.size(from: object["value"])))
        case "Circle": return BorderStyle(width: width, color: color, shape: .circle)
        case "Square": return BorderStyle(width: width, color: color, shape: .square)
        case let tag: throw RendererNodeJsonError.unknownShape(tag)
        }
    }

    func imageSource(_ key: String) throws -> ImageSource {
        let object = try jsonObject(required(key))
        let value = try object.string("value")

        switch try object.string("tag") {
        case "Bulletin": return .bulletin(value)
        case "Archive": return .archive(value)
        case let tag: throw RendererNodeJsonError.unknownImageSource(tag)
        }
    }
}

// MARK: - Scalars

private extension [String: Any] {
    func required(_ key: String) throws -> Any {
        guard let value = self[key], !(value is NSNull) else {
            throw RendererNodeJsonError.missingField(key)
        }
        return value
    }

    func object(_ key: String) -> [String: Any]? { self[key] as? [String: Any] }

    func array(_ key: String) -> [Any] { self[key] as? [Any] ?? [] }

    func string(_ key: String) throws -> String {
        guard let value = try required(key) as? String else { throw RendererNodeJsonError.missingField(key) }
        return value
    }

    func stringOrNil(_ key: String) -> String? { self[key] as? String }

    func boolean(_ key: String) -> Bool? { self[key] as? Bool }

    func size(_ key: String) throws -> Size { try Self.size(from: required(key)) }

    func sizeOrNil(_ key: String) throws -> Size? {
        guard let value = self[key], !(value is NSNull) else { return nil }
        return try Self.size(from: value)
    }

    /// Refused rather than clamped: a hand-written face gets an error naming
    /// what it got wrong, where a silently corrected size would draw something
    /// its author never asked for.
    static func size(from element: Any?) throws -> Size {
        guard let number = element as? NSNumber else {
            throw RendererNodeJsonError.sizeOutOfRange(String(describing: element))
        }
        let value = number.doubleValue
        guard value >= 0, value <= Limit.size, value == value.rounded() else {
            throw RendererNodeJsonError.sizeOutOfRange(number.stringValue)
        }
        return Size(value)
    }

    static func opacity(from element: Any?) throws -> UInt8 {
        guard let number = element as? NSNumber else {
            throw RendererNodeJsonError.opacityOutOfRange(String(describing: element))
        }
        let value = number.doubleValue
        guard value >= 0, value <= Double(UInt8.max), value == value.rounded() else {
            throw RendererNodeJsonError.opacityOutOfRange(number.stringValue)
        }
        return UInt8(value)
    }

    static func boolean(from element: Any?) throws -> Bool {
        guard let value = element as? Bool else { throw RendererNodeJsonError.missingField("value") }
        return value
    }

    static func blendingMode(from element: Any?) throws -> BlendingMode {
        guard let name = element as? String else { throw RendererNodeJsonError.missingField("value") }
        guard let mode = RendererWire.blendingModes[name] else { throw RendererNodeJsonError.unknownValue(name) }
        return mode
    }
}

// MARK: - Enums

/// The wire spelling of every renderer enum, in one place because it is a
/// contract with every other host: spelled out rather than derived from the
/// Swift case names, so a bindgen rename breaks the build instead of silently
/// changing which faces decode.
enum RendererWire {
    /// The largest size either direction may carry: the bound the Android host
    /// applies, so a face one host accepts is not refused by the other. The
    /// encoder writes nothing past it, because a face written larger than this
    /// could never be read back.
    static let maxSize = Size(Int32.max)

    static let blendingModes: [String: BlendingMode] = [
        "Normal": .normal, "Multiply": .multiply, "Screen": .screen, "Overlay": .overlay,
        "Darken": .darken, "Lighten": .lighten, "ColorDodge": .colorDodge, "ColorBurn": .colorBurn,
        "HardLight": .hardLight, "SoftLight": .softLight, "Difference": .difference,
        "Exclusion": .exclusion, "Hue": .hue, "Saturation": .saturation, "Color": .color,
        "Luminosity": .luminosity
    ]

    static let contentAlignments: [String: ContentAlignment] = [
        "TopStart": .topStart, "TopCenter": .topCenter, "TopEnd": .topEnd,
        "CenterStart": .centerStart, "Center": .center, "CenterEnd": .centerEnd,
        "BottomStart": .bottomStart, "BottomCenter": .bottomCenter, "BottomEnd": .bottomEnd
    ]

    static let arrangements: [String: Arrangement] = [
        "Start": .start, "End": .end, "Center": .center,
        "SpaceBetween": .spaceBetween, "SpaceAround": .spaceAround, "SpaceEvenly": .spaceEvenly
    ]

    static let typographyStyles: [String: TypographyStyle] = [
        "HeadlineLarge": .headlineLarge, "TitleMediumRegular": .titleMediumRegular,
        "BodyLargeRegular": .bodyLargeRegular, "BodyMediumRegular": .bodyMediumRegular,
        "BodySmallRegular": .bodySmallRegular
    ]

    static let colorTokens: [String: ColorToken] = [
        "FgPrimary": .fgPrimary, "FgSecondary": .fgSecondary, "FgTertiary": .fgTertiary,
        "BgSurfaceMain": .bgSurfaceMain, "BgSurfaceContainer": .bgSurfaceContainer,
        "BgSurfaceNested": .bgSurfaceNested,
        "FgSuccess": .fgSuccess, "FgError": .fgError, "FgWarning": .fgWarning
    ]

    static let buttonVariants: [String: ButtonVariant] = [
        "Primary": .primary, "Secondary": .secondary, "Text": .text
    ]

    static let imageFits: [String: ImageFit] = [
        "None": .none, "Fill": .fill, "Cover": .cover, "Contain": .contain, "ScaleDown": .scaleDown
    ]

    static let effects: [String: Effect] = ["Rainbow": .rainbow]

    /// The wire name of a value, read off the same table the decoder reads, so
    /// the two directions cannot drift apart.
    static func name<T: Hashable>(of value: T, in cases: [String: T]) -> String? {
        cases.first { $0.value == value }?.key
    }
}

private extension [String: Any] {
    func named<T>(_ key: String, _ cases: [String: T]) throws -> T? {
        guard let name = stringOrNil(key) else { return nil }
        guard let value = cases[name] else { throw RendererNodeJsonError.unknownValue(name) }
        return value
    }

    func contentAlignment(_ key: String) throws -> ContentAlignment? {
        try named(key, RendererWire.contentAlignments)
    }

    // Built whole for the same reason the shapes are: the alignment enums share
    // their names with SwiftUI's and cannot be written in a return type, so the
    // cases are only named where the initializer parameter infers them.
    func columnProps() throws -> ColumnProps {
        try ColumnProps(
            horizontalAlignment: named("horizontalAlignment", ["Start": .start, "Center": .center, "End": .end]),
            verticalArrangement: arrangement("verticalArrangement")
        )
    }

    func rowProps() throws -> RowProps {
        try RowProps(
            verticalAlignment: named("verticalAlignment", ["Top": .top, "Center": .center, "Bottom": .bottom]),
            horizontalArrangement: arrangement("horizontalArrangement")
        )
    }

    func arrangement(_ key: String) throws -> Arrangement? {
        try named(key, RendererWire.arrangements)
    }

    func typographyStyle(_ key: String) throws -> TypographyStyle? {
        try named(key, RendererWire.typographyStyles)
    }

    func colorToken(_ key: String) throws -> ColorToken? {
        try named(key, RendererWire.colorTokens)
    }

    func requiredColorToken(_ key: String) throws -> ColorToken {
        guard let token = try colorToken(key) else { throw RendererNodeJsonError.missingField(key) }
        return token
    }

    func buttonVariant(_ key: String) throws -> ButtonVariant? {
        try named(key, RendererWire.buttonVariants)
    }

    func imageFit(_ key: String) throws -> ImageFit? {
        try named(key, RendererWire.imageFits)
    }

    func effect(_ key: String) throws -> Effect {
        guard let effect: Effect = try named(key, RendererWire.effects) else {
            throw RendererNodeJsonError.missingField(key)
        }
        return effect
    }
}
