//! The Apple apps' door into astrid-core.
//!
//! The boundary is kept as small as the core's own: two doors and a callback, not a symbol per
//! feature.
//!
//! - [`run_rule`] — the **rules door**, [`astrid_core::rules::run_json`]. Synchronous and
//!   stateless: the pure contracts a view asks while it draws (what completing a task does, how a
//!   description renders). Nothing it answers depends on anything but the request.
//! - [`CoreClient::run`] — the **client door**, [`astrid_core::app::App::run_json`]. Async and
//!   stateful: the cache, the Outbox, the network.
//!
//! Both speak JSON in the API wire shape (`/api/v1`) that the Swift models already encode, so a
//! feature added to the core is a new `kind`, not a new symbol here, a regenerated binding and a
//! hand-written Swift mirror of its types.
//!
//! ## The rules of this file
//!
//! 1. **Nothing panics across the boundary.** A panic unwinding into Swift aborts the process; each
//!    door catches and answers with a failure in the core's own envelope, so a bug in the core is
//!    an error on screen rather than an app that vanishes.
//! 2. **The UI thread never waits on the core.** [`CoreClient::run`] is `async` in Swift; the work
//!    runs on the core's own Tokio pool.
//! 3. **Nothing platform-specific is decided here.** Credentials arrive through
//!    [`CredentialStore`], which the app implements over the Keychain.

use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use astrid_core::app::{background, App, Config, Failure, Response};
use astrid_core::platform::{PlatformError, SecureStore};

uniffi::setup_scaffolding!();

/// The version of astrid-core these bindings were built from, for an about box and a crash
/// report.
#[uniffi::export]
pub fn core_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

/// Answer one pure rule — see [`astrid_core::rules`]. Synchronous, and safe to call from any
/// thread, including the main one: no rule touches a cache, a clock or the network.
#[uniffi::export]
pub fn run_rule(request: String) -> String {
    catch_unwind(|| astrid_core::rules::run_json(&request)).unwrap_or_else(|_| {
        Response::failed(Failure::bad_request("the core panicked answering a rule")).to_json()
    })
}

/// The commands `run_blocking` answers: they read or write this machine's cache and nothing else.
const BLOCKING_KINDS: &[&str] = &[
    "tasks",
    "lists",
    "projects",
    "seedCache",
    "importJournalEntry",
];

/// Credentials at rest, implemented by the app over the Keychain.
///
/// Synchronous because the Keychain is: a Keychain read is a local call that answers in
/// microseconds, and making it async would buy nothing but a hop.
#[uniffi::export(with_foreign)]
pub trait CredentialStore: Send + Sync {
    fn get(&self, key: String) -> Option<String>;
    /// `false` when the Keychain refused the write.
    fn set(&self, key: String, value: String) -> bool;
    /// `false` when the Keychain refused the delete. Deleting what is not there is `true`.
    fn delete(&self, key: String) -> bool;
}

/// Adapts the app's store to the core's async trait.
struct ForeignSecureStore(Arc<dyn CredentialStore>);

#[async_trait::async_trait]
impl SecureStore for ForeignSecureStore {
    async fn get(&self, key: &str) -> Option<String> {
        self.0.get(key.to_string())
    }

    async fn set(&self, key: &str, value: &str) -> Result<(), PlatformError> {
        match self.0.set(key.to_string(), value.to_string()) {
            true => Ok(()),
            false => Err(PlatformError::Denied(format!("the Keychain refused {key}"))),
        }
    }

    async fn delete(&self, key: &str) -> Result<(), PlatformError> {
        match self.0.delete(key.to_string()) {
            true => Ok(()),
            false => Err(PlatformError::Denied(format!("the Keychain refused {key}"))),
        }
    }
}

/// Told when the cache moves: a colleague's edit arriving on the live stream, a sync pass, a
/// reminder coming due. `change_json` is the core's own vocabulary — `{"change":"task","id":…}`,
/// `{"change":"synced","taskIds":[…],"listIds":[…]}` and so on (`Change::to_json`).
///
/// Called on one of the core's threads, never the main one: the app hops to where it draws.
#[uniffi::export(with_foreign)]
pub trait ChangeListener: Send + Sync {
    fn on_change(&self, change_json: String);
}

/// Why the client could not start.
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum StartError {
    #[error("{message}")]
    Failed { message: String },
}

/// A running client: the cache, the Outbox, and — when asked — the loops that keep them current.
#[derive(uniffi::Object)]
pub struct CoreClient {
    app: Arc<App>,
    runtime: tokio::runtime::Runtime,
    /// Cleared by [`CoreClient::stop`], watched by the background loops.
    running: Arc<AtomicBool>,
}

#[uniffi::export]
impl CoreClient {
    /// Open the cache at `config_json`'s `cachePath` (`":memory:"` for a test) and wire everything
    /// to it.
    ///
    /// `background` starts the loops that keep the app current without being asked — the sync
    /// pass, the Outbox delivery, the live stream. A test, and a UI-test build that must never
    /// reach the network, passes `false`.
    #[uniffi::constructor]
    pub fn start(
        config_json: String,
        credentials: Arc<dyn CredentialStore>,
        background: bool,
    ) -> Result<Arc<Self>, StartError> {
        let failed = |message: String| StartError::Failed { message };
        let config: Config =
            serde_json::from_str(&config_json).map_err(|error| failed(error.to_string()))?;
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .thread_name("astrid-core")
            .build()
            .map_err(|error| failed(error.to_string()))?;
        let app = Arc::new(
            App::start(&config, Arc::new(ForeignSecureStore(credentials)))
                .map_err(|error| failed(error.to_string()))?,
        );
        let running = Arc::new(AtomicBool::new(true));
        if background {
            start_loops(&runtime, &app, &running);
        }
        Ok(Arc::new(CoreClient {
            app,
            runtime,
            running,
        }))
    }

    /// Run one command — see [`astrid_core::app::Command`] — and answer in the core's envelope.
    ///
    /// Runs on the core's pool, never the caller's thread, and never throws: every failure,
    /// including a panic inside the core, comes back as `{"ok":false,"error":…}`.
    pub async fn run(&self, request: String) -> String {
        let app = self.app.clone();
        match self
            .runtime
            .spawn(async move { app.run_json(&request).await })
            .await
        {
            Ok(answer) => answer,
            Err(error) => Response::failed(Failure::bad_request(format!(
                "the core failed answering a command: {error}"
            )))
            .to_json(),
        }
    }

    /// Run one command and wait for its answer on the calling thread.
    ///
    /// For the one read that must finish before the first frame — the tasks and lists a launch
    /// shows offline — and nothing else: everything else awaits `run`. Refuses rather than
    /// deadlocks when called from one of the core's own threads (a change listener that forgot to
    /// hop off it).
    ///
    /// Only the commands that stay on this machine — cache reads, and the local-only writes of the
    /// first launch after an upgrade. Anything that could wait on the network is refused: it would
    /// hold the main thread for as long as the network took. A panic in the core answers as a
    /// failure rather than taking the app down with it.
    pub fn run_blocking(&self, request: String) -> String {
        if tokio::runtime::Handle::try_current().is_ok() {
            return Response::failed(Failure::bad_request(
                "runBlocking was called from the core's own thread; await run instead",
            ))
            .to_json();
        }
        let kind = serde_json::from_str::<serde_json::Value>(&request)
            .ok()
            .and_then(|value| value.get("kind")?.as_str().map(str::to_string))
            .unwrap_or_default();
        if !BLOCKING_KINDS.contains(&kind.as_str()) {
            return Response::failed(Failure::bad_request(format!(
                "{kind} may reach the network; await run instead of runBlocking"
            )))
            .to_json();
        }
        catch_unwind(AssertUnwindSafe(|| {
            self.runtime.block_on(self.app.run_json(&request))
        }))
        .unwrap_or_else(|_| {
            Response::failed(Failure::bad_request(
                "the core panicked answering a command",
            ))
            .to_json()
        })
    }

    /// Hear every change to the cache from now on. The app subscribes once, not per screen.
    pub fn subscribe(&self, listener: Arc<dyn ChangeListener>) {
        self.app
            .realtime()
            .on_change(move |change| listener.on_change(change.to_json()));
    }

    /// Ask the background loops to stop at their next check. Commands still run afterwards.
    pub fn stop(&self) {
        self.running.store(false, Ordering::Relaxed);
    }
}

/// The loops a running app keeps going on its own — the same set the Windows shell starts.
fn start_loops(runtime: &tokio::runtime::Runtime, app: &Arc<App>, running: &Arc<AtomicBool>) {
    let keep_going = |running: &Arc<AtomicBool>| {
        let running = running.clone();
        move || running.load(Ordering::Relaxed)
    };
    runtime.spawn(background::sync_loop(
        app.clone(),
        keep_going(running),
        background::default_sync_interval(),
    ));
    runtime.spawn(background::outbox_loop(
        app.clone(),
        keep_going(running),
        app.outbox_nudge().clone(),
    ));
    runtime.spawn(background::reminder_loop(
        app.clone(),
        keep_going(running),
        background::REMINDER_INTERVAL,
    ));
    let (app, keep) = (app.clone(), keep_going(running));
    runtime.spawn(async move { background::realtime_loop(app, &keep).await });
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use std::sync::Mutex;

    #[derive(Default)]
    struct MemoryCredentials(Mutex<HashMap<String, String>>);

    impl CredentialStore for MemoryCredentials {
        fn get(&self, key: String) -> Option<String> {
            self.0.lock().unwrap().get(&key).cloned()
        }
        fn set(&self, key: String, value: String) -> bool {
            self.0.lock().unwrap().insert(key, value);
            true
        }
        fn delete(&self, key: String) -> bool {
            self.0.lock().unwrap().remove(&key);
            true
        }
    }

    #[test]
    fn the_rules_door_answers_in_the_core_envelope() {
        let answer = run_rule(r#"{"kind":"renderMarkdown","text":"hi"}"#.into());
        assert!(answer.starts_with(r#"{"ok":true"#), "{answer}");
    }

    #[test]
    fn an_unreadable_rule_is_a_failure_not_a_crash() {
        let answer = run_rule("not json".into());
        assert!(answer.contains(r#""ok":false"#), "{answer}");
    }

    #[derive(Default)]
    struct Heard(Mutex<Vec<String>>);

    impl ChangeListener for Heard {
        fn on_change(&self, change_json: String) {
            self.0.lock().unwrap().push(change_json);
        }
    }

    #[test]
    fn a_listener_hears_changes_in_the_cores_words() {
        let core = CoreClient::start(
            r#"{"cachePath":":memory:","platform":"ios-app"}"#.into(),
            Arc::new(MemoryCredentials::default()),
            false,
        )
        .expect("starts");
        let heard = Arc::new(Heard::default());
        core.subscribe(heard.clone());
        core.app
            .realtime()
            .publish(astrid_core::realtime::Change::Task("t1".into()));
        assert_eq!(
            heard.0.lock().unwrap().as_slice(),
            [r#"{"change":"task","id":"t1"}"#.to_string()]
        );
    }

    #[test]
    fn a_blocking_read_answers_on_the_calling_thread() {
        let core = CoreClient::start(
            r#"{"cachePath":":memory:"}"#.into(),
            Arc::new(MemoryCredentials::default()),
            false,
        )
        .expect("starts");
        let answer = core.run_blocking(r#"{"kind":"tasks"}"#.into());
        assert_eq!(answer, r#"{"ok":true,"value":[]}"#);
    }

    #[test]
    fn the_client_door_runs_a_command_on_its_own_pool() {
        let core = CoreClient::start(
            r#"{"cachePath":":memory:"}"#.into(),
            Arc::new(MemoryCredentials::default()),
            false,
        )
        .expect("starts");
        // Awaited from a runtime of the test's own, as Swift awaits from its executor.
        let answer = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(core.run(r#"{"kind":"lists"}"#.into()));
        assert!(answer.starts_with(r#"{"ok":true"#), "{answer}");
    }

    /// Only what stays on this machine may hold the calling thread: a command that could wait on
    /// the network is refused rather than freezing the main thread for as long as it takes.
    #[test]
    fn a_blocking_call_that_could_reach_the_network_is_refused() {
        let core = CoreClient::start(
            r#"{"cachePath":":memory:","baseUrl":"https://astrid.cc","platform":"ios-app"}"#
                .to_string(),
            Arc::new(MemoryCredentials::default()),
            false,
        )
        .expect("starts");
        let answer = core.run_blocking(r#"{"kind":"sync"}"#.to_string());
        assert!(answer.contains(r#""ok":false"#), "{answer}");
        assert!(answer.contains("await run"), "{answer}");
        let projects = core.run_blocking(r#"{"kind":"projects"}"#.to_string());
        assert!(projects.contains(r#""ok":true"#), "{projects}");
    }
}
