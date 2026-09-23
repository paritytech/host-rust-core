import SwiftUI

extension View {
    /// `alignment` is where the body sits once a fill modifier has stretched
    /// its frame. A stack sizes to its widest child, so without this a filled
    /// node centres its content instead of honouring its own alignment.
    @ViewBuilder
    func applyWidgetNodeModifiers(
        _ modifiers: CustomMessageWidgetNode.Modifiers,
        alignment: Alignment = .center
    ) -> some View {
        self
            // 1. Inner padding
            .padding(modifiers.padding)
            // 2. Background color + clip
            .modifier(NodeBackgroundModifier(background: modifiers.background))
            // 3. Border overlay
            .modifier(NodeBorderModifier(border: modifiers.border))
            // 4. Frame constraints (size / fill)
            .modifier(NodeFrameModifier(modifiers: modifiers, alignment: alignment))
            // 5. Compositing, over the node and its background but under the margin
            .modifier(NodeCompositingModifier(modifiers: modifiers))
            // 6. Outer margin
            .padding(modifiers.margin)
    }
}

// MARK: - Compositing

private struct NodeCompositingModifier: ViewModifier {
    let modifiers: CustomMessageWidgetNode.Modifiers

    func body(content: Content) -> some View {
        content
            .opacity(modifiers.opacity ?? 1)
            .blendMode(modifiers.blendingMode ?? .normal)
            // `.opacity(0)` only stops the drawing, so a node the product hid
            // would still take the press: hit testing follows the opacity.
            .allowsHitTesting((modifiers.opacity ?? 1) > 0)
    }
}

// MARK: - Background

private struct NodeBackgroundModifier: ViewModifier {
    let background: CustomMessageWidgetNode.Background?

    func body(content: Content) -> some View {
        if let background {
            if let shape = background.shape {
                content
                    .background(background.color, in: shape)
                    .clipShape(shape)
            } else {
                content
                    .background(background.color)
            }
        } else {
            content
        }
    }
}

// MARK: - Border

private struct NodeBorderModifier: ViewModifier {
    let border: CustomMessageWidgetNode.Border?

    func body(content: Content) -> some View {
        if let border {
            if let shape = border.shape {
                content
                    .overlay(shape.stroke(border.color, lineWidth: border.width))
            } else {
                content
                    .overlay(Rectangle().stroke(border.color, lineWidth: border.width))
            }
        } else {
            content
        }
    }
}

// MARK: - Frame

private struct NodeFrameModifier: ViewModifier {
    let modifiers: CustomMessageWidgetNode.Modifiers
    let alignment: Alignment

    func body(content: Content) -> some View {
        switch (modifiers.hasWidthConstraint, modifiers.hasHeightConstraint) {
        case (true, true):
            content
                .frame(
                    minWidth: modifiers.minWidth,
                    maxWidth: modifiers.fillWidth ? .infinity : nil,
                    minHeight: modifiers.minHeight,
                    maxHeight: modifiers.fillHeight ? .infinity : nil,
                    alignment: alignment
                )
                .frame(width: modifiers.width, height: modifiers.height, alignment: alignment)
        case (true, false):
            content
                .frame(
                    minWidth: modifiers.minWidth,
                    maxWidth: modifiers.fillWidth ? .infinity : nil,
                    alignment: alignment
                )
                .frame(width: modifiers.width, alignment: alignment)
        case (false, true):
            content
                .frame(
                    minHeight: modifiers.minHeight,
                    maxHeight: modifiers.fillHeight ? .infinity : nil,
                    alignment: alignment
                )
                .frame(height: modifiers.height, alignment: alignment)
        case (false, false):
            content
        }
    }
}
