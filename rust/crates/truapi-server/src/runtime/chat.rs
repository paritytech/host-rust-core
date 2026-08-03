//! Connection-scoped Chat streams shared by product and native entrypoints.

use std::collections::{HashMap, VecDeque};
use std::sync::{Arc, Mutex};

use futures::StreamExt;
use futures::channel::mpsc;
use truapi::versioned::chat::{
    HostChatActionSubscribeItem, ProductChatCustomMessageRenderChannelItem,
    ProductChatCustomMessageRenderChannelRequest,
};
use truapi::{Subscription, v01};

use crate::host_core::ProductRuntimeError;
use crate::subscription::Spawner;

const ACTION_BUFFER_CAPACITY: usize = 64;

struct RendererState {
    generation: u64,
    work: mpsc::UnboundedSender<ProductChatCustomMessageRenderChannelItem>,
    renders: HashMap<String, mpsc::UnboundedSender<v01::CustomRendererNode>>,
}

#[derive(Default)]
struct State {
    actions: Option<mpsc::UnboundedSender<HostChatActionSubscribeItem>>,
    action_buffer: VecDeque<HostChatActionSubscribeItem>,
    renderer: Option<RendererState>,
    next_renderer_generation: u64,
    closed: bool,
}

/// Mutable Chat protocol state owned by one product connection.
pub(crate) struct ChatConnection {
    state: Arc<Mutex<State>>,
    spawner: Spawner,
}

impl ChatConnection {
    /// Create empty Chat state for one product connection.
    pub(crate) fn new(spawner: Spawner) -> Self {
        Self {
            state: Arc::new(Mutex::new(State::default())),
            spawner,
        }
    }

    /// Open the product's action subscription and drain buffered actions first.
    pub(crate) fn subscribe_actions(&self) -> Subscription<HostChatActionSubscribeItem> {
        let (sender, receiver) = mpsc::unbounded();
        let mut state = self.state.lock().expect("chat state mutex poisoned");
        if state.closed {
            return Subscription::empty();
        }
        for item in state.action_buffer.drain(..) {
            let _ = sender.unbounded_send(item);
        }
        state.actions = Some(sender);
        Subscription::new(Box::pin(receiver))
    }

    /// Publish one native action, buffering it until the product subscribes.
    pub(crate) fn publish_action(
        &self,
        mut action: HostChatActionSubscribeItem,
    ) -> Result<(), ProductRuntimeError> {
        let mut state = self.state.lock().expect("chat state mutex poisoned");
        if state.closed {
            return Err(ProductRuntimeError::Closed);
        }
        if let Some(sender) = state.actions.as_ref() {
            match sender.unbounded_send(action) {
                Ok(()) => return Ok(()),
                Err(error) => action = error.into_inner(),
            }
            state.actions = None;
        }
        if state.action_buffer.len() == ACTION_BUFFER_CAPACITY {
            return Err(ProductRuntimeError::BufferFull);
        }
        state.action_buffer.push_back(action);
        Ok(())
    }

    /// Register the product's paired renderer streams for this connection.
    pub(crate) fn register_renderer(
        &self,
        mut requests: Subscription<ProductChatCustomMessageRenderChannelRequest>,
    ) -> Subscription<ProductChatCustomMessageRenderChannelItem> {
        let (work, receiver) = mpsc::unbounded();
        let generation = {
            let mut state = self.state.lock().expect("chat state mutex poisoned");
            if state.closed {
                return Subscription::empty();
            }
            let generation = state.next_renderer_generation;
            state.next_renderer_generation += 1;
            state.renderer = Some(RendererState {
                generation,
                work,
                renders: HashMap::new(),
            });
            generation
        };

        let state = self.state.clone();
        (self.spawner)(Box::pin(async move {
            while let Some(request) = requests.next().await {
                let mut state = state.lock().expect("chat state mutex poisoned");
                let Some(renderer) = state
                    .renderer
                    .as_mut()
                    .filter(|renderer| renderer.generation == generation)
                else {
                    break;
                };
                let ProductChatCustomMessageRenderChannelRequest::V1(request) = request;
                match request {
                    v01::ProductChatCustomMessageRenderChannelRequest::Update {
                        message_id,
                        node,
                    } => {
                        if let Some(sender) = renderer.renders.get(&message_id)
                            && sender.unbounded_send(node).is_err()
                        {
                            renderer.renders.remove(&message_id);
                        }
                    }
                    v01::ProductChatCustomMessageRenderChannelRequest::Failed { message_id } => {
                        renderer.renders.remove(&message_id);
                    }
                }
            }
            let mut state = state.lock().expect("chat state mutex poisoned");
            if state
                .renderer
                .as_ref()
                .is_some_and(|renderer| renderer.generation == generation)
            {
                state.renderer = None;
            }
        }));

        Subscription::new(Box::pin(receiver))
    }

    /// Send one render request and return its native replacement-tree stream.
    pub(crate) fn render_custom_message(
        &self,
        message_id: String,
        message_type: String,
        payload: Vec<u8>,
    ) -> Result<Subscription<v01::CustomRendererNode>, ProductRuntimeError> {
        let (sender, receiver) = mpsc::unbounded();
        let mut state = self.state.lock().expect("chat state mutex poisoned");
        if state.closed {
            return Err(ProductRuntimeError::Closed);
        }
        let renderer = state
            .renderer
            .as_mut()
            .ok_or(ProductRuntimeError::Unsupported)?;
        renderer.renders.insert(message_id.clone(), sender);
        let item = ProductChatCustomMessageRenderChannelItem::V1(
            v01::ProductChatCustomMessageRenderChannelItem {
                message_id: message_id.clone(),
                message_type,
                payload,
            },
        );
        if renderer.work.unbounded_send(item).is_err() {
            renderer.renders.remove(&message_id);
            return Err(ProductRuntimeError::Unsupported);
        }
        Ok(Subscription::new(Box::pin(receiver)))
    }

    /// Close all connection-scoped Chat streams and discard buffered work.
    pub(crate) fn close(&self) {
        let mut state = self.state.lock().expect("chat state mutex poisoned");
        state.closed = true;
        state.actions = None;
        state.action_buffer.clear();
        state.renderer = None;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures::executor::block_on;
    use truapi::v01::{ChatActionPayload, ChatMessageContent, CustomRendererNode};

    fn action(text: &str) -> HostChatActionSubscribeItem {
        HostChatActionSubscribeItem::V1(v01::HostChatActionSubscribeItem {
            room_id: "room".to_string(),
            peer: "alice".to_string(),
            payload: ChatActionPayload::MessagePosted(ChatMessageContent::Text {
                text: text.to_string(),
            }),
        })
    }

    fn connection() -> ChatConnection {
        ChatConnection::new(crate::subscription::thread_per_subscription_spawner())
    }

    #[test]
    fn buffered_actions_are_drained_in_fifo_order() {
        let connection = connection();
        connection.publish_action(action("first")).unwrap();
        connection.publish_action(action("second")).unwrap();

        let mut actions = connection.subscribe_actions();
        assert_eq!(block_on(actions.next()), Some(action("first")));
        assert_eq!(block_on(actions.next()), Some(action("second")));
    }

    #[test]
    fn full_startup_action_buffer_is_reported() {
        let connection = connection();
        for index in 0..ACTION_BUFFER_CAPACITY {
            connection
                .publish_action(action(&index.to_string()))
                .unwrap();
        }

        assert!(matches!(
            connection.publish_action(action("overflow")),
            Err(ProductRuntimeError::BufferFull)
        ));
    }

    #[test]
    fn closing_discards_buffered_actions() {
        let connection = connection();
        connection.publish_action(action("discard me")).unwrap();
        connection.close();

        let mut actions = connection.subscribe_actions();
        assert_eq!(block_on(actions.next()), None);
        assert!(matches!(
            connection.publish_action(action("too late")),
            Err(ProductRuntimeError::Closed)
        ));
    }

    #[test]
    fn renderer_updates_are_routed_by_message_id() {
        let connection = connection();
        let (requests_tx, requests_rx) = mpsc::unbounded();
        let mut work = connection.register_renderer(Subscription::new(Box::pin(requests_rx)));
        let mut first = connection
            .render_custom_message("one".into(), "vote".into(), vec![1])
            .unwrap();
        let mut second = connection
            .render_custom_message("two".into(), "balance".into(), vec![2])
            .unwrap();

        assert_eq!(
            block_on(work.next()),
            Some(ProductChatCustomMessageRenderChannelItem::V1(
                v01::ProductChatCustomMessageRenderChannelItem {
                    message_id: "one".into(),
                    message_type: "vote".into(),
                    payload: vec![1],
                }
            ))
        );
        assert_eq!(
            block_on(work.next()),
            Some(ProductChatCustomMessageRenderChannelItem::V1(
                v01::ProductChatCustomMessageRenderChannelItem {
                    message_id: "two".into(),
                    message_type: "balance".into(),
                    payload: vec![2],
                }
            ))
        );

        let node = CustomRendererNode::String {
            text: "second".into(),
        };
        requests_tx
            .unbounded_send(ProductChatCustomMessageRenderChannelRequest::V1(
                v01::ProductChatCustomMessageRenderChannelRequest::Update {
                    message_id: "two".into(),
                    node: node.clone(),
                },
            ))
            .unwrap();

        assert_eq!(block_on(second.next()), Some(node));

        requests_tx
            .unbounded_send(ProductChatCustomMessageRenderChannelRequest::V1(
                v01::ProductChatCustomMessageRenderChannelRequest::Failed {
                    message_id: "one".into(),
                },
            ))
            .unwrap();
        assert_eq!(block_on(first.next()), None);
    }

    #[test]
    fn renderer_accepts_multiple_replacements_for_one_message() {
        let connection = connection();
        let (requests_tx, requests_rx) = mpsc::unbounded();
        let mut work = connection.register_renderer(Subscription::new(Box::pin(requests_rx)));
        let mut render = connection
            .render_custom_message("one".into(), "counter".into(), vec![])
            .unwrap();
        assert!(block_on(work.next()).is_some());

        for text in ["first", "second"] {
            requests_tx
                .unbounded_send(ProductChatCustomMessageRenderChannelRequest::V1(
                    v01::ProductChatCustomMessageRenderChannelRequest::Update {
                        message_id: "one".into(),
                        node: CustomRendererNode::String { text: text.into() },
                    },
                ))
                .unwrap();
        }

        assert_eq!(
            block_on(render.next()),
            Some(CustomRendererNode::String {
                text: "first".into()
            })
        );
        assert_eq!(
            block_on(render.next()),
            Some(CustomRendererNode::String {
                text: "second".into()
            })
        );
    }

    #[test]
    fn replacing_renderer_closes_old_work_and_render_instances() {
        let connection = connection();
        let (_first_requests_tx, first_requests_rx) = mpsc::unbounded();
        let mut first_work =
            connection.register_renderer(Subscription::new(Box::pin(first_requests_rx)));
        let mut first_render = connection
            .render_custom_message("old".into(), "vote".into(), vec![])
            .unwrap();
        assert!(block_on(first_work.next()).is_some());

        let (_second_requests_tx, second_requests_rx) = mpsc::unbounded();
        let mut second_work =
            connection.register_renderer(Subscription::new(Box::pin(second_requests_rx)));

        assert_eq!(block_on(first_work.next()), None);
        assert_eq!(block_on(first_render.next()), None);

        let mut second_render = connection
            .render_custom_message("new".into(), "vote".into(), vec![])
            .unwrap();
        assert!(block_on(second_work.next()).is_some());
        connection.close();
        assert_eq!(block_on(second_work.next()), None);
        assert_eq!(block_on(second_render.next()), None);
    }

    #[test]
    fn separate_connections_cannot_observe_each_others_actions_or_renders() {
        let first = connection();
        let second = connection();
        let mut first_actions = first.subscribe_actions();
        let mut second_actions = second.subscribe_actions();

        first.publish_action(action("first only")).unwrap();
        second.publish_action(action("second only")).unwrap();
        assert_eq!(block_on(first_actions.next()), Some(action("first only")));
        assert_eq!(block_on(second_actions.next()), Some(action("second only")));

        let (first_requests_tx, first_requests_rx) = mpsc::unbounded();
        let mut first_work =
            first.register_renderer(Subscription::new(Box::pin(first_requests_rx)));
        let (_second_requests_tx, second_requests_rx) = mpsc::unbounded();
        let mut second_work =
            second.register_renderer(Subscription::new(Box::pin(second_requests_rx)));
        let mut first_render = first
            .render_custom_message("same-id".into(), "first".into(), vec![])
            .unwrap();
        let mut second_render = second
            .render_custom_message("same-id".into(), "second".into(), vec![])
            .unwrap();
        assert!(block_on(first_work.next()).is_some());
        assert!(block_on(second_work.next()).is_some());

        let node = CustomRendererNode::String {
            text: "first product".into(),
        };
        first_requests_tx
            .unbounded_send(ProductChatCustomMessageRenderChannelRequest::V1(
                v01::ProductChatCustomMessageRenderChannelRequest::Update {
                    message_id: "same-id".into(),
                    node: node.clone(),
                },
            ))
            .unwrap();
        assert_eq!(block_on(first_render.next()), Some(node));

        second.close();
        assert_eq!(block_on(second_render.next()), None);
    }
}
