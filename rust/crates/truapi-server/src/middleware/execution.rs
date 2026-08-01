//! Trusted executable-kind filtering for service surfaces.

use truapi_platform::ProductExecutionKind;

/// Immutable execution-kind filter bound to one product connection.
#[derive(Debug, Clone, Copy)]
pub struct ExecutionFilter {
    actual: Option<ProductExecutionKind>,
}

impl ExecutionFilter {
    /// Build an unrestricted filter for direct dispatcher embeddings.
    pub fn unrestricted() -> Self {
        Self { actual: None }
    }

    /// Build a filter for a host-assigned executable kind.
    pub fn for_execution(actual: ProductExecutionKind) -> Self {
        Self {
            actual: Some(actual),
        }
    }

    /// Return whether the connection may access a service requiring `required`.
    pub fn allows(&self, required: ProductExecutionKind) -> bool {
        self.actual.is_none_or(|actual| actual == required)
    }
}
