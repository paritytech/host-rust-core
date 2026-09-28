//! The one tokio runtime every native core task runs on: subscriptions and
//! background loops spawned through the core's [`Spawner`](crate::subscription::Spawner),
//! the work behind every host-called entry point, and the WebSocket bridge's
//! connections.

use std::io;
use std::sync::{Arc, Mutex, OnceLock};

use futures::future::BoxFuture;
use tokio::runtime::{Handle, Runtime};
use tokio::task::JoinHandle;

use crate::subscription::Spawner;

/// Process-wide executor shared by every native host runtime and product bridge.
///
/// The runtime intentionally lives until process exit. Host runtimes and
/// product bridges have independent lifecycles, so shutting the executor down
/// with any one of them would interrupt the others.
pub struct SharedNativeExecutor {
    runtime: Runtime,
}

impl SharedNativeExecutor {
    fn new() -> io::Result<Self> {
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .thread_name("truapi-native-worker")
            .enable_all()
            .build()
            .map_err(|err| io::Error::other(err.to_string()))?;
        Ok(Self { runtime })
    }

    /// Handle for spawning onto the runtime from any thread, inside it or not.
    pub fn handle(&self) -> Handle {
        self.runtime.handle().clone()
    }

    /// Number of worker threads the runtime schedules tasks on.
    pub fn worker_threads(&self) -> usize {
        self.runtime.metrics().num_workers()
    }

    /// Spawner that runs core tasks on this runtime, whichever thread spawns them.
    pub fn spawner(&self) -> Spawner {
        let handle = self.handle();
        Arc::new(move |task: BoxFuture<'static, ()>| {
            handle.spawn(task);
        })
    }

    /// Start `work` on this runtime and return a future for its output that
    /// any executor can poll, so a host thread only waits and never runs core
    /// code. Dropping the returned future aborts the task, as dropping the work
    /// itself would. A panic in `work` resumes in the caller.
    pub fn run<T: Send + 'static>(
        &self,
        work: impl Future<Output = T> + Send + 'static,
    ) -> impl Future<Output = T> + Send + 'static {
        let mut task = AbortOnDrop(self.runtime.spawn(work));
        async move {
            match (&mut task.0).await {
                Ok(output) => output,
                Err(error) => match error.try_into_panic() {
                    Ok(panic) => std::panic::resume_unwind(panic),
                    Err(error) => panic!("core task ended without an answer: {error}"),
                },
            }
        }
    }
}

static SHARED_NATIVE_EXECUTOR: OnceLock<SharedNativeExecutor> = OnceLock::new();
static SHARED_NATIVE_EXECUTOR_INIT: Mutex<()> = Mutex::new(());

/// The shared executor, built on first use; the flag is `true` for the call
/// that built it.
pub fn shared_native_executor() -> io::Result<(&'static SharedNativeExecutor, bool)> {
    if let Some(executor) = SHARED_NATIVE_EXECUTOR.get() {
        return Ok((executor, false));
    }

    // Serialize fallible initialization without caching a transient thread
    // creation failure for the rest of the process.
    let _guard = SHARED_NATIVE_EXECUTOR_INIT
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    if let Some(executor) = SHARED_NATIVE_EXECUTOR.get() {
        return Ok((executor, false));
    }

    let initialized = SHARED_NATIVE_EXECUTOR
        .set(SharedNativeExecutor::new()?)
        .is_ok();
    let executor = SHARED_NATIVE_EXECUTOR
        .get()
        .ok_or_else(|| io::Error::other("shared native executor initialization failed"))?;
    Ok((executor, initialized))
}

struct AbortOnDrop<T>(JoinHandle<T>);

impl<T> Drop for AbortOnDrop<T> {
    fn drop(&mut self) {
        self.0.abort();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures::FutureExt;

    #[test]
    fn shared_executor_uses_multithread_scheduler() {
        let (executor, _) = shared_native_executor().expect("shared native executor");
        let handle = executor.handle();
        assert_eq!(
            handle.runtime_flavor(),
            tokio::runtime::RuntimeFlavor::MultiThread
        );

        // Each task blocks one runtime worker at the barrier. They can only
        // both complete if the executor actually schedules them concurrently
        // on distinct worker threads.
        if executor.worker_threads() < 2 {
            return;
        }
        let barrier = Arc::new(std::sync::Barrier::new(2));
        let first = handle.spawn({
            let barrier = barrier.clone();
            async move {
                let worker = std::thread::current().id();
                barrier.wait();
                worker
            }
        });
        let second = handle.spawn(async move {
            let worker = std::thread::current().id();
            barrier.wait();
            worker
        });

        let client = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("test runtime");
        let (first, second) = client.block_on(async { tokio::join!(first, second) });
        assert_ne!(
            first.expect("first dispatch task"),
            second.expect("second dispatch task"),
        );
    }

    /// Core tasks run on the shared native runtime, including those spawned
    /// from a thread outside any runtime, such as a host thread.
    #[test]
    fn spawned_core_tasks_run_on_the_shared_runtime() {
        let (executor, _) = shared_native_executor().expect("shared native executor");
        let (runtime_tx, runtime_rx) = std::sync::mpsc::channel();

        executor.spawner()(
            async move {
                let runtime = Handle::try_current().map(|handle| handle.id());
                runtime_tx.send(runtime.ok()).unwrap();
            }
            .boxed(),
        );

        let ran_on = runtime_rx
            .recv_timeout(std::time::Duration::from_secs(5))
            .expect("spawned core task never ran");
        assert_eq!(ran_on, Some(executor.handle().id()));
    }

    fn core() -> &'static SharedNativeExecutor {
        shared_native_executor().expect("shared native executor").0
    }

    #[test]
    fn run_executes_the_work_on_the_core_runtime_for_a_host_thread_caller() {
        let ran_on = futures::executor::block_on(core().run(async {
            Handle::try_current().map(|handle| handle.id()).ok()
        }));

        assert_eq!(ran_on, Some(core().handle().id()));
    }

    /// Hosts stop long-running calls such as serving a paired session by
    /// cancelling the task awaiting them, so the core task must stop too.
    #[test]
    fn dropping_the_call_aborts_the_core_task() {
        struct SignalOnDrop(std::sync::mpsc::Sender<()>);
        impl Drop for SignalOnDrop {
            fn drop(&mut self) {
                let _ = self.0.send(());
            }
        }

        let (started_tx, started_rx) = std::sync::mpsc::channel();
        let (dropped_tx, dropped_rx) = std::sync::mpsc::channel();
        let mut call = Box::pin(core().run(async move {
            let _guard = SignalOnDrop(dropped_tx);
            started_tx.send(()).unwrap();
            futures::future::pending::<()>().await;
        }));
        let waker = futures::task::noop_waker();
        assert!(
            call.as_mut()
                .poll(&mut core::task::Context::from_waker(&waker))
                .is_pending()
        );
        started_rx
            .recv_timeout(std::time::Duration::from_secs(5))
            .expect("core task never started");

        drop(call);

        dropped_rx
            .recv_timeout(std::time::Duration::from_secs(5))
            .expect("core task kept running after its caller went away");
    }

    #[test]
    fn a_panic_in_the_core_task_resumes_in_the_caller() {
        let outcome = std::panic::catch_unwind(|| {
            futures::executor::block_on(core().run(async { panic!("core failure") }))
        });

        let panic = outcome.expect_err("the caller must see the panic");
        assert_eq!(panic.downcast_ref::<&str>(), Some(&"core failure"));
    }

    #[test]
    fn shared_executor_is_reused() {
        let (first, _) = shared_native_executor().expect("first executor access");
        let (second, initialized) = shared_native_executor().expect("second executor access");

        assert!(!initialized);
        assert_eq!(first.handle().id(), second.handle().id());
    }
}
