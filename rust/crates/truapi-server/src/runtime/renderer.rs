//! Connection-scoped Renderer policy shared by product and native entrypoints.

use crate::host_core::ProductRuntimeError;

/// Renderer access policy shared by the wire runtime and the native
/// entrypoints: only a Worker execution with an active session draws bodies or
/// receives their actions. Unlike Chat, no native adapter is required.
pub(crate) fn renderer_access_for(
    execution_kind: truapi_platform::ProductExecutionKind,
    has_session: bool,
) -> Result<(), ProductRuntimeError> {
    if execution_kind != truapi_platform::ProductExecutionKind::Worker || !has_session {
        return Err(ProductRuntimeError::Denied);
    }
    Ok(())
}
