import SwiftUI

extension View {
    @ViewBuilder
    func applyWidgetNodeModifiers(_ modifiers: CustomMessageWidgetNode.Modifiers) -> some View {
        self
            // 1. Inner padding
            .padding(modifiers.padding)
            // 2. Background color + clip
            .modifier(NodeBackgroundModifier(background: modifiers.background))
            // 3. Border overlay
            .modifier(NodeBorderModifier(border: modifiers.border))
            // 4. Frame constraints (size / fill)
            .modifier(NodeFrameModifier(modifiers: modifiers))
            // 6. Outer margin
            .padding(modifiers.margin)
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

    func body(content: Content) -> some View {
        switch (modifiers.hasWidthConstraint, modifiers.hasHeightConstraint) {
        case (true, true):
            content
                .frame(
                    minWidth: modifiers.minWidth,
                    maxWidth: modifiers.fillWidth ? .infinity : nil,
                    minHeight: modifiers.minHeight,
                    maxHeight: modifiers.fillHeight ? .infinity : nil
                )
                .frame(width: modifiers.width, height: modifiers.height)
        case (true, false):
            content
                .frame(minWidth: modifiers.minWidth, maxWidth: modifiers.fillWidth ? .infinity : nil)
                .frame(width: modifiers.width)
        case (false, true):
            content
                .frame(minHeight: modifiers.minHeight, maxHeight: modifiers.fillHeight ? .infinity : nil)
                .frame(height: modifiers.height)
        case (false, false):
            content
        }
    }
}
