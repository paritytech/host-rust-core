//! Runs a user host-script under `bun`, driving a host through the injected
//! `truapi` global.
//!
//! The Rust CLI owns the flow: it starts the host, then spawns `js/runner.ts`
//! (which connects the `@parity/truapi` client to the host and evaluates the
//! user script). The child's exit status becomes the host command's status, so
//! `truapi-host pairing-host --script foo.ts` *is* the test — there is no
//! separate bun orchestrator.

use std::ffi::OsString;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::ExitStatus;
use std::process::Stdio;
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;

use crate::terminal_ui::{self, SystemEvent, UiHandle};

/// Host topology serving the product script.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ScriptHostRole {
    PairingHost,
    SigningHost,
}

impl ScriptHostRole {
    fn as_env_value(self) -> &'static str {
        match self {
            Self::PairingHost => "pairing-host",
            Self::SigningHost => "signing-host",
        }
    }
}

const SCRATCH_TEMPLATE: &str = r#"#!/usr/bin/env bun

// Scripts can use packages installed next to the script or in a parent project.

const result = await truapi.account.getUserId();
if (!result.isOk()) {
  throw new Error(`getUserId failed: ${JSON.stringify(result.error)}`);
}

console.log('user id', result.value);
"#;

/// Runner bundle shipped next to the binary in a release archive. It has
/// `@parity/truapi` compiled in, so a downloaded install runs product scripts
/// without a source checkout.
const PACKAGED_RUNNER: &str = "runner.js";

/// Locate the host-script runner.
fn runner_path() -> PathBuf {
    resolve_runner(
        std::env::var_os("TRUAPI_HOST_RUNNER"),
        std::env::current_exe().ok().as_deref(),
    )
}

/// Explicit override first, then the bundle beside the running binary, then the
/// checkout's `js/runner.ts`.
///
/// The checkout copy imports `@parity/truapi` by relative path, so it only
/// works from a built source tree; the packaged bundle is what makes an
/// installed binary self-sufficient.
fn resolve_runner(explicit: Option<OsString>, executable: Option<&Path>) -> PathBuf {
    if let Some(path) = explicit {
        return PathBuf::from(path);
    }
    let packaged = executable.and_then(packaged_runner);
    if let Some(packaged) = packaged.filter(|path| path.is_file()) {
        return packaged;
    }
    Path::new(env!("CARGO_MANIFEST_DIR")).join("js/runner.ts")
}

fn packaged_runner(executable: &Path) -> Option<PathBuf> {
    let executable = fs::canonicalize(executable).unwrap_or_else(|_| executable.to_path_buf());
    let directory = executable.parent()?;
    // `current` can move during an update; the runner must stay on this binary's version.
    if let Some(versions) = directory.parent()
        && versions.file_name().is_some_and(|name| name == "versions")
    {
        return Some(
            versions
                .join(env!("CARGO_PKG_VERSION"))
                .join(PACKAGED_RUNNER),
        );
    }
    Some(directory.join(PACKAGED_RUNNER))
}

/// Create a durable, uniquely-named TypeScript scratch file seeded with the
/// public TrUAPI example.
pub fn create_scratch_script(directory: &Path) -> Result<PathBuf> {
    fs::create_dir_all(directory)
        .with_context(|| format!("create script directory {}", directory.display()))?;
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    for sequence in 0..100 {
        let path = directory.join(format!(
            "script-{timestamp}-{}-{sequence}.ts",
            std::process::id()
        ));
        let mut file = match OpenOptions::new().write(true).create_new(true).open(&path) {
            Ok(file) => file,
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(error) => {
                return Err(error)
                    .with_context(|| format!("create scratch script {}", path.display()));
            }
        };
        file.write_all(SCRATCH_TEMPLATE.as_bytes())
            .with_context(|| format!("write scratch script {}", path.display()))?;
        return Ok(path);
    }
    anyhow::bail!(
        "could not allocate a unique scratch script in {}",
        directory.display()
    );
}

/// Open the script in the configured terminal editor and wait for it to exit.
pub async fn edit(script: &Path) -> Result<ExitStatus> {
    let specification = configured_editor();
    let (program, arguments) = parse_editor(&specification)?;
    let mut command = Command::new(program);
    command
        .args(arguments)
        .arg(script)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit());
    command
        .status()
        .await
        .with_context(|| format!("failed to launch editor {specification:?}"))
}

fn configured_editor() -> String {
    std::env::var("VISUAL")
        .ok()
        .filter(|value| !value.trim().is_empty())
        .or_else(|| {
            std::env::var("EDITOR")
                .ok()
                .filter(|value| !value.trim().is_empty())
        })
        .unwrap_or_else(|| {
            if cfg!(windows) {
                "notepad".to_string()
            } else {
                "vi".to_string()
            }
        })
}

fn parse_editor(specification: &str) -> Result<(String, Vec<String>)> {
    let mut parts = shlex::split(specification)
        .with_context(|| format!("invalid editor command {specification:?}"))?
        .into_iter();
    let program = parts
        .next()
        .with_context(|| format!("editor command is empty: {specification:?}"))?;
    Ok((program, parts.collect()))
}

/// Run `script` against the host serving frames at `frame_url`, as product
/// `product_id`. Inherits stdio so the script's output and any CLI confirmation
/// prompts share the terminal. Returns the child's exit status.
pub async fn run(
    frame_url: &str,
    product_id: &str,
    script: &Path,
    host_role: ScriptHostRole,
) -> Result<ExitStatus> {
    let mut command = command(frame_url, product_id, script, host_role)?;
    terminal_ui::output_event(SystemEvent::ScriptStarted);
    command
        .status()
        .await
        .context("failed to spawn `bun` for the host script (is bun installed?)")
}

/// Run a product script with stdout and stderr streamed into the terminal UI.
pub async fn run_captured(
    frame_url: &str,
    product_id: &str,
    script: &Path,
    ui: UiHandle,
    host_role: ScriptHostRole,
) -> Result<ExitStatus> {
    let mut command = command(frame_url, product_id, script, host_role)?;
    terminal_ui::output_event(SystemEvent::ScriptStarted);
    command
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);
    let mut child = command
        .spawn()
        .context("failed to spawn `bun` for the host script (is bun installed?)")?;
    let stdout = child.stdout.take().context("capture script stdout")?;
    let stderr = child.stderr.take().context("capture script stderr")?;
    let stdout_ui = ui.clone();
    let stdout_task = async move {
        let mut lines = BufReader::new(stdout).lines();
        while let Some(line) = lines.next_line().await? {
            stdout_ui.script_stdout(line);
        }
        Ok::<(), std::io::Error>(())
    };
    let stderr_task = async move {
        let mut lines = BufReader::new(stderr).lines();
        while let Some(line) = lines.next_line().await? {
            ui.script_stderr(line);
        }
        Ok::<(), std::io::Error>(())
    };
    let (status, stdout, stderr) = tokio::join!(child.wait(), stdout_task, stderr_task);
    stdout.context("read script stdout")?;
    stderr.context("read script stderr")?;
    status.context("wait for host script")
}

fn command(
    frame_url: &str,
    product_id: &str,
    script: &Path,
    host_role: ScriptHostRole,
) -> Result<Command> {
    let runner = runner_path();
    if !runner.exists() {
        anyhow::bail!(
            "host-script runner not found at {}; set TRUAPI_HOST_RUNNER",
            runner.display()
        );
    }
    let script = script
        .canonicalize()
        .with_context(|| format!("script not found: {}", script.display()))?;

    let mut command = Command::new("bun");
    command
        .arg("run")
        .arg(&runner)
        .env("TRUAPI_FRAME_URL", frame_url)
        .env("TRUAPI_PRODUCT_ID", product_id)
        .env("TRUAPI_SCRIPT", &script)
        .env("TRUAPI_CLI_HOST_ROLE", host_role.as_env_value());
    Ok(command)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The override exists so a packaged install can be pointed at a working
    /// copy; it has to win over the bundle sitting next to the binary.
    #[test]
    fn an_explicit_runner_overrides_the_packaged_bundle() {
        let install = tempfile::tempdir().unwrap();
        let executable = install.path().join("truapi-host");
        fs::write(install.path().join(PACKAGED_RUNNER), "packaged").unwrap();

        assert_eq!(
            resolve_runner(
                Some(OsString::from("/somewhere/custom.ts")),
                Some(&executable)
            ),
            Path::new("/somewhere/custom.ts")
        );
    }

    /// What makes a downloaded binary able to run product scripts at all.
    #[test]
    fn a_bundle_beside_the_binary_is_preferred_over_the_checkout() {
        let install = tempfile::tempdir().unwrap();
        let executable = install.path().join("truapi-host");
        let bundle = install.path().join(PACKAGED_RUNNER);
        fs::write(&executable, "binary").unwrap();
        fs::write(&bundle, "packaged").unwrap();

        assert_eq!(
            resolve_runner(None, Some(&executable)),
            bundle.canonicalize().unwrap()
        );
    }

    #[cfg(unix)]
    #[test]
    fn the_packaged_bundle_tracks_the_running_version_through_installer_symlinks() -> Result<()> {
        use std::os::unix::fs::symlink;

        let home = tempfile::tempdir()?;
        let root = home.path().join("share/truapi-host");
        let version = root.join("versions").join(env!("CARGO_PKG_VERSION"));
        let bin = home.path().join("bin");
        fs::create_dir_all(&version)?;
        fs::create_dir_all(&bin)?;

        let installed_executable = version.join("truapi-host");
        let installed_bundle = version.join(PACKAGED_RUNNER);
        fs::write(&installed_executable, "binary")?;
        fs::write(&installed_bundle, "packaged")?;
        let current = root.join("current");
        symlink(
            Path::new("versions").join(env!("CARGO_PKG_VERSION")),
            &current,
        )?;

        let entrypoint = bin.join("truapi-host");
        symlink(root.join("current/truapi-host"), &entrypoint)?;

        let expected = installed_bundle.canonicalize()?;
        assert_eq!(resolve_runner(None, Some(&entrypoint)), expected);

        let next_version = root.join("versions/next");
        fs::create_dir_all(&next_version)?;
        fs::write(next_version.join("truapi-host"), "next binary")?;
        fs::write(next_version.join(PACKAGED_RUNNER), "next runner")?;
        fs::remove_file(&current)?;
        symlink("versions/next", current)?;

        assert_eq!(
            resolve_runner(None, Some(&entrypoint)),
            expected,
            "a running binary keeps using its matching runner after current moves"
        );
        Ok(())
    }

    #[test]
    fn a_source_build_falls_back_to_the_checkout_runner() {
        let install = tempfile::tempdir().unwrap();
        let executable = install.path().join("truapi-host");

        assert_eq!(
            resolve_runner(None, Some(&executable)),
            Path::new(env!("CARGO_MANIFEST_DIR")).join("js/runner.ts")
        );
    }

    #[test]
    fn scratch_script_starts_as_a_bun_script_with_dependency_free_example() -> Result<()> {
        let temporary = tempfile::tempdir()?;

        let script = create_scratch_script(temporary.path())?;
        let contents = fs::read_to_string(script)?;

        assert_eq!(
            contents,
            r#"#!/usr/bin/env bun

// Scripts can use packages installed next to the script or in a parent project.

const result = await truapi.account.getUserId();
if (!result.isOk()) {
  throw new Error(`getUserId failed: ${JSON.stringify(result.error)}`);
}

console.log('user id', result.value);
"#
        );
        Ok(())
    }

    #[test]
    fn host_scripts_are_run_by_bun() -> Result<()> {
        let temporary = tempfile::tempdir()?;
        let script = temporary.path().join("script.ts");
        fs::write(&script, "console.log('hello');\n")?;

        let command = command(
            "ws://127.0.0.1:1234",
            "example.dot",
            &script,
            ScriptHostRole::SigningHost,
        )?;
        let command = command.as_std();
        let arguments = command.get_args().collect::<Vec<_>>();

        assert_eq!(command.get_program(), std::ffi::OsStr::new("bun"));
        assert_eq!(arguments[0], std::ffi::OsStr::new("run"));
        assert_eq!(arguments[1], runner_path());
        assert_eq!(
            command
                .get_envs()
                .find_map(|(key, value)| { (key == "TRUAPI_CLI_HOST_ROLE").then_some(value) }),
            Some(Some(std::ffi::OsStr::new("signing-host")))
        );
        Ok(())
    }

    #[test]
    fn editor_command_accepts_quoted_arguments_without_a_shell() -> Result<()> {
        let (program, arguments) = parse_editor("code --wait \"profile one\"")?;

        assert_eq!(program, "code");
        assert_eq!(arguments, ["--wait", "profile one"]);
        Ok(())
    }
}
