//! Typed native projection of the recursive custom-renderer tree.

use std::sync::{Arc, Mutex};

use futures::StreamExt;
use futures::future::{AbortHandle, Abortable};
use truapi::{Subscription, v01};

use crate::subscription::Spawner;

/// Native custom-renderer node discriminator.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum NativeCustomRendererNodeKind {
    /// Empty node.
    Nil,
    /// Raw text child.
    String,
    /// Generic container.
    Box,
    /// Vertical layout.
    Column,
    /// Horizontal layout.
    Row,
    /// Flexible space.
    Spacer,
    /// Styled text.
    Text,
    /// Interactive button.
    Button,
    /// Editable text field.
    TextField,
}

/// Native semantic color token.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum NativeCustomRendererColorToken {
    /// Primary foreground.
    FgPrimary,
    /// Secondary foreground.
    FgSecondary,
    /// Tertiary foreground.
    FgTertiary,
    /// Main surface background.
    BgSurfaceMain,
    /// Container surface background.
    BgSurfaceContainer,
    /// Nested surface background.
    BgSurfaceNested,
    /// Success foreground.
    FgSuccess,
    /// Error foreground.
    FgError,
    /// Warning foreground.
    FgWarning,
}

/// Native typography token.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum NativeCustomRendererTypographyStyle {
    /// Large headline.
    HeadlineLarge,
    /// Medium regular title.
    TitleMediumRegular,
    /// Large regular body.
    BodyLargeRegular,
    /// Medium regular body.
    BodyMediumRegular,
    /// Small regular body.
    BodySmallRegular,
}

/// Native button style.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum NativeCustomRendererButtonVariant {
    /// Primary button.
    Primary,
    /// Secondary button.
    Secondary,
    /// Text-only button.
    Text,
}

/// Native two-dimensional alignment.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum NativeCustomRendererContentAlignment {
    /// Top-start.
    TopStart,
    /// Top-center.
    TopCenter,
    /// Top-end.
    TopEnd,
    /// Center-start.
    CenterStart,
    /// Centered.
    Center,
    /// Center-end.
    CenterEnd,
    /// Bottom-start.
    BottomStart,
    /// Bottom-center.
    BottomCenter,
    /// Bottom-end.
    BottomEnd,
}

/// Native horizontal alignment.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum NativeCustomRendererHorizontalAlignment {
    /// Start edge.
    Start,
    /// Center.
    Center,
    /// End edge.
    End,
}

/// Native vertical alignment.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum NativeCustomRendererVerticalAlignment {
    /// Top edge.
    Top,
    /// Center.
    Center,
    /// Bottom edge.
    Bottom,
}

/// Native layout arrangement.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum NativeCustomRendererArrangement {
    /// Pack at the start.
    Start,
    /// Pack at the end.
    End,
    /// Pack at the center.
    Center,
    /// Space between children.
    SpaceBetween,
    /// Space around children.
    SpaceAround,
    /// Equal space between and around children.
    SpaceEvenly,
}

/// Native renderer dimensions in logical pixels.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct NativeCustomRendererDimensions {
    /// Top dimension.
    pub top: u64,
    /// End dimension.
    pub end: u64,
    /// Optional bottom dimension.
    pub bottom: Option<u64>,
    /// Optional start dimension.
    pub start: Option<u64>,
}

/// Native renderer shape.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum NativeCustomRendererShape {
    /// Rounded rectangle.
    Rounded {
        /// Corner radius.
        radius: u64,
    },
    /// Circle.
    Circle,
}

/// Native renderer background.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct NativeCustomRendererBackground {
    /// Background color.
    pub color: NativeCustomRendererColorToken,
    /// Optional background shape.
    pub shape: Option<NativeCustomRendererShape>,
}

/// Native renderer border.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct NativeCustomRendererBorderStyle {
    /// Border width.
    pub width: u64,
    /// Border color.
    pub color: NativeCustomRendererColorToken,
    /// Optional border shape.
    pub shape: Option<NativeCustomRendererShape>,
}

/// Typed native renderer modifier.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum NativeCustomRendererModifier {
    /// Outer spacing.
    Margin {
        /// Spacing dimensions.
        dimensions: NativeCustomRendererDimensions,
    },
    /// Inner spacing.
    Padding {
        /// Spacing dimensions.
        dimensions: NativeCustomRendererDimensions,
    },
    /// Background fill.
    Background {
        /// Background style.
        background: NativeCustomRendererBackground,
    },
    /// Border.
    Border {
        /// Border style.
        border: NativeCustomRendererBorderStyle,
    },
    /// Fixed height.
    Height {
        /// Height in logical pixels.
        height: u64,
    },
    /// Fixed width.
    Width {
        /// Width in logical pixels.
        width: u64,
    },
    /// Minimum width.
    MinWidth {
        /// Width in logical pixels.
        width: u64,
    },
    /// Minimum height.
    MinHeight {
        /// Height in logical pixels.
        height: u64,
    },
    /// Fill available width.
    FillWidth {
        /// Whether filling is enabled.
        enabled: bool,
    },
    /// Fill available height.
    FillHeight {
        /// Whether filling is enabled.
        enabled: bool,
    },
}

/// Native properties for a box node.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct NativeCustomRendererBoxProps {
    /// Optional content alignment.
    pub content_alignment: Option<NativeCustomRendererContentAlignment>,
}

/// Native properties for a column node.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct NativeCustomRendererColumnProps {
    /// Optional horizontal alignment.
    pub horizontal_alignment: Option<NativeCustomRendererHorizontalAlignment>,
    /// Optional vertical arrangement.
    pub vertical_arrangement: Option<NativeCustomRendererArrangement>,
}

/// Native properties for a row node.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct NativeCustomRendererRowProps {
    /// Optional vertical alignment.
    pub vertical_alignment: Option<NativeCustomRendererVerticalAlignment>,
    /// Optional horizontal arrangement.
    pub horizontal_arrangement: Option<NativeCustomRendererArrangement>,
}

/// Native properties for a text node.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct NativeCustomRendererTextProps {
    /// Optional typography token.
    pub style: Option<NativeCustomRendererTypographyStyle>,
    /// Optional color token.
    pub color: Option<NativeCustomRendererColorToken>,
}

/// Native properties for a button node.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct NativeCustomRendererButtonProps {
    /// Button label.
    pub text: String,
    /// Optional button style.
    pub variant: Option<NativeCustomRendererButtonVariant>,
    /// Optional enabled override.
    pub enabled: Option<bool>,
    /// Optional loading override.
    pub loading: Option<bool>,
    /// Optional action identifier.
    pub click_action: Option<String>,
}

/// Native properties for a text-field node.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct NativeCustomRendererTextFieldProps {
    /// Current text.
    pub text: String,
    /// Optional placeholder.
    pub placeholder: Option<String>,
    /// Optional label.
    pub label: Option<String>,
    /// Optional enabled override.
    pub enabled: Option<bool>,
    /// Optional value-change action identifier.
    pub value_change_action: Option<String>,
}

/// Opaque recursive custom-renderer node exposed through typed accessors.
#[derive(Debug, uniffi::Object)]
pub struct NativeCustomRendererNode {
    inner: v01::CustomRendererNode,
}

#[uniffi::export]
impl NativeCustomRendererNode {
    /// Return this node's discriminator.
    pub fn kind(&self) -> NativeCustomRendererNodeKind {
        match &self.inner {
            v01::CustomRendererNode::Nil => NativeCustomRendererNodeKind::Nil,
            v01::CustomRendererNode::String { .. } => NativeCustomRendererNodeKind::String,
            v01::CustomRendererNode::Box(_) => NativeCustomRendererNodeKind::Box,
            v01::CustomRendererNode::Column(_) => NativeCustomRendererNodeKind::Column,
            v01::CustomRendererNode::Row(_) => NativeCustomRendererNodeKind::Row,
            v01::CustomRendererNode::Spacer(_) => NativeCustomRendererNodeKind::Spacer,
            v01::CustomRendererNode::Text(_) => NativeCustomRendererNodeKind::Text,
            v01::CustomRendererNode::Button(_) => NativeCustomRendererNodeKind::Button,
            v01::CustomRendererNode::TextField(_) => NativeCustomRendererNodeKind::TextField,
        }
    }

    /// Return raw text for a string node.
    pub fn string_text(&self) -> Option<String> {
        match &self.inner {
            v01::CustomRendererNode::String { text } => Some(text.clone()),
            _ => None,
        }
    }

    /// Return this component node's modifiers.
    pub fn modifiers(&self) -> Vec<NativeCustomRendererModifier> {
        self.component_modifiers()
            .iter()
            .cloned()
            .map(Into::into)
            .collect()
    }

    /// Return this component node's recursive children.
    pub fn children(&self) -> Vec<Arc<NativeCustomRendererNode>> {
        self.component_children()
            .iter()
            .cloned()
            .map(|inner| Arc::new(Self { inner }))
            .collect()
    }

    /// Return box properties when this is a box node.
    pub fn box_props(&self) -> Option<NativeCustomRendererBoxProps> {
        match &self.inner {
            v01::CustomRendererNode::Box(component) => Some(NativeCustomRendererBoxProps {
                content_alignment: component.props.content_alignment.map(Into::into),
            }),
            _ => None,
        }
    }

    /// Return column properties when this is a column node.
    pub fn column_props(&self) -> Option<NativeCustomRendererColumnProps> {
        match &self.inner {
            v01::CustomRendererNode::Column(component) => Some(NativeCustomRendererColumnProps {
                horizontal_alignment: component.props.horizontal_alignment.map(Into::into),
                vertical_arrangement: component.props.vertical_arrangement.map(Into::into),
            }),
            _ => None,
        }
    }

    /// Return row properties when this is a row node.
    pub fn row_props(&self) -> Option<NativeCustomRendererRowProps> {
        match &self.inner {
            v01::CustomRendererNode::Row(component) => Some(NativeCustomRendererRowProps {
                vertical_alignment: component.props.vertical_alignment.map(Into::into),
                horizontal_arrangement: component.props.horizontal_arrangement.map(Into::into),
            }),
            _ => None,
        }
    }

    /// Return text properties when this is a text node.
    pub fn text_props(&self) -> Option<NativeCustomRendererTextProps> {
        match &self.inner {
            v01::CustomRendererNode::Text(component) => Some(NativeCustomRendererTextProps {
                style: component.props.style.map(Into::into),
                color: component.props.color.map(Into::into),
            }),
            _ => None,
        }
    }

    /// Return button properties when this is a button node.
    pub fn button_props(&self) -> Option<NativeCustomRendererButtonProps> {
        match &self.inner {
            v01::CustomRendererNode::Button(component) => Some(NativeCustomRendererButtonProps {
                text: component.props.text.clone(),
                variant: component.props.variant.map(Into::into),
                enabled: component.props.enabled.0,
                loading: component.props.loading.0,
                click_action: component.props.click_action.clone(),
            }),
            _ => None,
        }
    }

    /// Return text-field properties when this is a text-field node.
    pub fn text_field_props(&self) -> Option<NativeCustomRendererTextFieldProps> {
        match &self.inner {
            v01::CustomRendererNode::TextField(component) => {
                Some(NativeCustomRendererTextFieldProps {
                    text: component.props.text.clone(),
                    placeholder: component.props.placeholder.clone(),
                    label: component.props.label.clone(),
                    enabled: component.props.enabled.0,
                    value_change_action: component.props.value_change_action.clone(),
                })
            }
            _ => None,
        }
    }
}

impl NativeCustomRendererNode {
    fn component_modifiers(&self) -> &[v01::Modifier] {
        match &self.inner {
            v01::CustomRendererNode::Box(component) => &component.modifiers,
            v01::CustomRendererNode::Column(component) => &component.modifiers,
            v01::CustomRendererNode::Row(component) => &component.modifiers,
            v01::CustomRendererNode::Spacer(component) => &component.modifiers,
            v01::CustomRendererNode::Text(component) => &component.modifiers,
            v01::CustomRendererNode::Button(component) => &component.modifiers,
            v01::CustomRendererNode::TextField(component) => &component.modifiers,
            v01::CustomRendererNode::Nil | v01::CustomRendererNode::String { .. } => &[],
        }
    }

    fn component_children(&self) -> &[v01::CustomRendererNode] {
        match &self.inner {
            v01::CustomRendererNode::Box(component) => &component.children,
            v01::CustomRendererNode::Column(component) => &component.children,
            v01::CustomRendererNode::Row(component) => &component.children,
            v01::CustomRendererNode::Spacer(component) => &component.children,
            v01::CustomRendererNode::Text(component) => &component.children,
            v01::CustomRendererNode::Button(component) => &component.children,
            v01::CustomRendererNode::TextField(component) => &component.children,
            v01::CustomRendererNode::Nil | v01::CustomRendererNode::String { .. } => &[],
        }
    }
}

/// Observer implemented by a native host to receive renderer tree replacements.
#[uniffi::export(callback_interface)]
pub trait NativeCustomRendererObserver: Send + Sync {
    /// Deliver a complete replacement tree.
    fn on_update(&self, node: Arc<NativeCustomRendererNode>);

    /// Report that the renderer stream ended.
    fn on_complete(&self);
}

/// Cancellable native observation of one custom-message render instance.
#[derive(uniffi::Object)]
pub struct NativeCustomRendererSubscription {
    abort: Mutex<Option<AbortHandle>>,
}

#[uniffi::export]
impl NativeCustomRendererSubscription {
    /// Stop delivering renderer updates to the native observer.
    pub fn cancel(&self) {
        if let Some(abort) = self
            .abort
            .lock()
            .expect("native renderer subscription mutex poisoned")
            .take()
        {
            abort.abort();
        }
    }
}

impl Drop for NativeCustomRendererSubscription {
    fn drop(&mut self) {
        if let Some(abort) = self
            .abort
            .get_mut()
            .expect("native renderer subscription mutex poisoned")
            .take()
        {
            abort.abort();
        }
    }
}

#[cfg_attr(not(feature = "ws-bridge"), allow(dead_code))]
pub(crate) fn observe_renderer(
    mut stream: Subscription<v01::CustomRendererNode>,
    observer: Arc<dyn NativeCustomRendererObserver>,
    spawner: Spawner,
) -> Arc<NativeCustomRendererSubscription> {
    let (abort, registration) = AbortHandle::new_pair();
    (spawner)(Box::pin(async move {
        let completed = Abortable::new(
            async move {
                while let Some(inner) = stream.next().await {
                    observer.on_update(Arc::new(NativeCustomRendererNode { inner }));
                }
                observer.on_complete();
            },
            registration,
        )
        .await;
        let _ = completed;
    }));
    Arc::new(NativeCustomRendererSubscription {
        abort: Mutex::new(Some(abort)),
    })
}

impl From<v01::Dimensions> for NativeCustomRendererDimensions {
    fn from(value: v01::Dimensions) -> Self {
        Self {
            top: value.top.0,
            end: value.end.0,
            bottom: value.bottom.map(|size| size.0),
            start: value.start.map(|size| size.0),
        }
    }
}

impl From<v01::ColorToken> for NativeCustomRendererColorToken {
    fn from(value: v01::ColorToken) -> Self {
        match value {
            v01::ColorToken::FgPrimary => Self::FgPrimary,
            v01::ColorToken::FgSecondary => Self::FgSecondary,
            v01::ColorToken::FgTertiary => Self::FgTertiary,
            v01::ColorToken::BgSurfaceMain => Self::BgSurfaceMain,
            v01::ColorToken::BgSurfaceContainer => Self::BgSurfaceContainer,
            v01::ColorToken::BgSurfaceNested => Self::BgSurfaceNested,
            v01::ColorToken::FgSuccess => Self::FgSuccess,
            v01::ColorToken::FgError => Self::FgError,
            v01::ColorToken::FgWarning => Self::FgWarning,
        }
    }
}

impl From<v01::TypographyStyle> for NativeCustomRendererTypographyStyle {
    fn from(value: v01::TypographyStyle) -> Self {
        match value {
            v01::TypographyStyle::HeadlineLarge => Self::HeadlineLarge,
            v01::TypographyStyle::TitleMediumRegular => Self::TitleMediumRegular,
            v01::TypographyStyle::BodyLargeRegular => Self::BodyLargeRegular,
            v01::TypographyStyle::BodyMediumRegular => Self::BodyMediumRegular,
            v01::TypographyStyle::BodySmallRegular => Self::BodySmallRegular,
        }
    }
}

impl From<v01::ButtonVariant> for NativeCustomRendererButtonVariant {
    fn from(value: v01::ButtonVariant) -> Self {
        match value {
            v01::ButtonVariant::Primary => Self::Primary,
            v01::ButtonVariant::Secondary => Self::Secondary,
            v01::ButtonVariant::Text => Self::Text,
        }
    }
}

impl From<v01::ContentAlignment> for NativeCustomRendererContentAlignment {
    fn from(value: v01::ContentAlignment) -> Self {
        match value {
            v01::ContentAlignment::TopStart => Self::TopStart,
            v01::ContentAlignment::TopCenter => Self::TopCenter,
            v01::ContentAlignment::TopEnd => Self::TopEnd,
            v01::ContentAlignment::CenterStart => Self::CenterStart,
            v01::ContentAlignment::Center => Self::Center,
            v01::ContentAlignment::CenterEnd => Self::CenterEnd,
            v01::ContentAlignment::BottomStart => Self::BottomStart,
            v01::ContentAlignment::BottomCenter => Self::BottomCenter,
            v01::ContentAlignment::BottomEnd => Self::BottomEnd,
        }
    }
}

impl From<v01::HorizontalAlignment> for NativeCustomRendererHorizontalAlignment {
    fn from(value: v01::HorizontalAlignment) -> Self {
        match value {
            v01::HorizontalAlignment::Start => Self::Start,
            v01::HorizontalAlignment::Center => Self::Center,
            v01::HorizontalAlignment::End => Self::End,
        }
    }
}

impl From<v01::VerticalAlignment> for NativeCustomRendererVerticalAlignment {
    fn from(value: v01::VerticalAlignment) -> Self {
        match value {
            v01::VerticalAlignment::Top => Self::Top,
            v01::VerticalAlignment::Center => Self::Center,
            v01::VerticalAlignment::Bottom => Self::Bottom,
        }
    }
}

impl From<v01::Arrangement> for NativeCustomRendererArrangement {
    fn from(value: v01::Arrangement) -> Self {
        match value {
            v01::Arrangement::Start => Self::Start,
            v01::Arrangement::End => Self::End,
            v01::Arrangement::Center => Self::Center,
            v01::Arrangement::SpaceBetween => Self::SpaceBetween,
            v01::Arrangement::SpaceAround => Self::SpaceAround,
            v01::Arrangement::SpaceEvenly => Self::SpaceEvenly,
        }
    }
}

impl From<v01::Shape> for NativeCustomRendererShape {
    fn from(value: v01::Shape) -> Self {
        match value {
            v01::Shape::Rounded { radius } => Self::Rounded { radius: radius.0 },
            v01::Shape::Circle => Self::Circle,
        }
    }
}

impl From<v01::Background> for NativeCustomRendererBackground {
    fn from(value: v01::Background) -> Self {
        Self {
            color: value.color.into(),
            shape: value.shape.map(Into::into),
        }
    }
}

impl From<v01::BorderStyle> for NativeCustomRendererBorderStyle {
    fn from(value: v01::BorderStyle) -> Self {
        Self {
            width: value.width.0,
            color: value.color.into(),
            shape: value.shape.map(Into::into),
        }
    }
}

impl From<v01::Modifier> for NativeCustomRendererModifier {
    fn from(value: v01::Modifier) -> Self {
        match value {
            v01::Modifier::Margin(dimensions) => Self::Margin {
                dimensions: dimensions.into(),
            },
            v01::Modifier::Padding(dimensions) => Self::Padding {
                dimensions: dimensions.into(),
            },
            v01::Modifier::Background(background) => Self::Background {
                background: background.into(),
            },
            v01::Modifier::Border(border) => Self::Border {
                border: border.into(),
            },
            v01::Modifier::Height { height } => Self::Height { height: height.0 },
            v01::Modifier::Width { width } => Self::Width { width: width.0 },
            v01::Modifier::MinWidth { width } => Self::MinWidth { width: width.0 },
            v01::Modifier::MinHeight { height } => Self::MinHeight { height: height.0 },
            v01::Modifier::FillWidth { enabled } => Self::FillWidth { enabled },
            v01::Modifier::FillHeight { enabled } => Self::FillHeight { enabled },
        }
    }
}

#[cfg(test)]
mod tests {
    use parity_scale_codec::{Compact, OptionBool};

    use super::*;

    #[test]
    fn projects_recursive_renderer_nodes_into_typed_native_values() {
        let node = NativeCustomRendererNode {
            inner: v01::CustomRendererNode::Column(v01::Component {
                modifiers: vec![v01::Modifier::Padding(v01::Dimensions {
                    top: Compact(12),
                    end: Compact(8),
                    bottom: None,
                    start: Some(Compact(4)),
                })],
                props: v01::ColumnProps {
                    horizontal_alignment: Some(v01::HorizontalAlignment::Center),
                    vertical_arrangement: Some(v01::Arrangement::SpaceBetween),
                },
                children: vec![
                    v01::CustomRendererNode::String {
                        text: "Votes: 1".to_string(),
                    },
                    v01::CustomRendererNode::Button(v01::Component {
                        modifiers: Vec::new(),
                        props: v01::ButtonProps {
                            text: "Vote".to_string(),
                            variant: Some(v01::ButtonVariant::Primary),
                            enabled: OptionBool(Some(true)),
                            loading: OptionBool(None),
                            click_action: Some("vote".to_string()),
                        },
                        children: Vec::new(),
                    }),
                ],
            }),
        };

        assert_eq!(node.kind(), NativeCustomRendererNodeKind::Column);
        assert_eq!(
            node.column_props(),
            Some(NativeCustomRendererColumnProps {
                horizontal_alignment: Some(NativeCustomRendererHorizontalAlignment::Center),
                vertical_arrangement: Some(NativeCustomRendererArrangement::SpaceBetween),
            })
        );
        assert_eq!(
            node.modifiers(),
            vec![NativeCustomRendererModifier::Padding {
                dimensions: NativeCustomRendererDimensions {
                    top: 12,
                    end: 8,
                    bottom: None,
                    start: Some(4),
                },
            }]
        );

        let children = node.children();
        assert_eq!(children.len(), 2);
        assert_eq!(children[0].kind(), NativeCustomRendererNodeKind::String);
        assert_eq!(children[0].string_text().as_deref(), Some("Votes: 1"));
        assert_eq!(children[1].kind(), NativeCustomRendererNodeKind::Button);
        assert_eq!(
            children[1].button_props(),
            Some(NativeCustomRendererButtonProps {
                text: "Vote".to_string(),
                variant: Some(NativeCustomRendererButtonVariant::Primary),
                enabled: Some(true),
                loading: None,
                click_action: Some("vote".to_string()),
            })
        );
    }
}
