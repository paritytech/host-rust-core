//! Runs a user host-script under `bun`, driving a host through the injected
//! `truapi` global.
//!
//! The Rust CLI owns the flow: it starts the host, then spawns `js/runner.ts`
//! (which connects the `@parity/truapi` client to the host and evaluates the
//! user script). The child's exit status becomes the host command's status, so
//! `truapi-host pairing-host --script foo.ts` *is* the test — there is no
//! separate bun orchestrator.

use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::ExitStatus;
use std::process::Stdio;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::terminal_ui::{self, SystemEvent, UiHandle};
use anyhow::{Context, Result};
use sha2::{Digest, Sha256};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::{Child, Command};

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

/// Host-owned executable bundle measured before a product runtime is created.
pub struct PreparedScript {
    bundle: Vec<u8>,
    artifact_identity: String,
    working_directory: PathBuf,
}

impl PreparedScript {
    /// Stable identity of the exact bytes supplied to Bun.
    pub fn artifact_identity(&self) -> &str {
        &self.artifact_identity
    }
}

const SCRATCH_TEMPLATE: &str = r#"#!/usr/bin/env bun

// Scripts can use packages installed next to the script or in a parent project.
const cyanBold = "\u001b[1;36m";
const green = "\u001b[32m";
const reset = "\u001b[0m";

console.log(`${cyanBold}\n🚀 TrUAPI script\n${reset}`);

const result = await truapi.account.getUserId();
if (!result.isOk()) {
  throw new Error(`getUserId failed: ${JSON.stringify(result.error)}`);
}
console.log(`${green}user id:${reset}`, result.value);
"#;

/// Locate `js/runner.ts`, shipped alongside the crate.
///
/// Overridable with `TRUAPI_HOST_RUNNER` for packaged/relocated builds.
fn runner_path() -> PathBuf {
    if let Ok(path) = std::env::var("TRUAPI_HOST_RUNNER") {
        return PathBuf::from(path);
    }
    Path::new(env!("CARGO_MANIFEST_DIR")).join("js/runner.ts")
}

fn bundle_auditor_path(runner: &Path) -> PathBuf {
    runner.with_file_name("audit-bundle.ts")
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

/// Bundle the full statically reachable product executable, reject unresolved
/// executable imports, and measure the exact resulting bytes.
pub async fn prepare(script: &Path) -> Result<PreparedScript> {
    let runner = runner_path();
    if !runner.exists() {
        anyhow::bail!(
            "host-script runner not found at {}; set TRUAPI_HOST_RUNNER",
            runner.display()
        );
    }
    let auditor = bundle_auditor_path(&runner);
    if !auditor.exists() {
        anyhow::bail!(
            "host-script bundle auditor not found at {}",
            auditor.display()
        );
    }
    let script = script
        .canonicalize()
        .with_context(|| format!("script not found: {}", script.display()))?;
    let runner = runner
        .canonicalize()
        .with_context(|| format!("resolve host-script runner {}", runner.display()))?;
    let script_specifier = serde_json::to_string(
        script
            .to_str()
            .context("product script path is not valid UTF-8")?,
    )?;
    let runner_specifier = serde_json::to_string(
        runner
            .to_str()
            .context("host-script runner path is not valid UTF-8")?,
    )?;
    let temporary = tempfile::tempdir().context("create product bundle directory")?;
    let entry_path = temporary.path().join("entry.ts");
    let bundle_path = temporary.path().join("product.mjs");
    fs::write(
        &entry_path,
        format!(
            "import {{ runProductScript }} from {runner_specifier};\n\
             runProductScript(() => import({script_specifier}));\n"
        ),
    )
    .context("write product bundle entry")?;

    let output = Command::new("bun")
        .arg("build")
        .arg(&entry_path)
        .arg("--target=bun")
        .arg("--format=esm")
        .arg("--minify")
        .arg("--packages=bundle")
        .arg("--outfile")
        .arg(&bundle_path)
        .output()
        .await
        .context("failed to spawn `bun build` for the host script (is bun installed?)")?;
    if !output.status.success() {
        anyhow::bail!(
            "failed to bundle product script: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        );
    }

    let audit = Command::new("bun")
        .arg("run")
        .arg(&auditor)
        .arg(&bundle_path)
        .output()
        .await
        .context("failed to audit the product bundle")?;
    if !audit.status.success() {
        anyhow::bail!(
            "product bundle is not self-contained: {}",
            String::from_utf8_lossy(&audit.stderr).trim()
        );
    }

    let bundle = fs::read(&bundle_path).context("read product executable bundle")?;
    let artifact_identity = format!("sha256:{}", hex::encode(Sha256::digest(&bundle)));
    let working_directory = script
        .parent()
        .context("product script has no parent directory")?
        .to_path_buf();
    Ok(PreparedScript {
        bundle,
        artifact_identity,
        working_directory,
    })
}

/// Run a prepared product bundle against the host serving `frame_url`.
pub async fn run(
    frame_url: &str,
    product_id: &str,
    script: &PreparedScript,
    host_role: ScriptHostRole,
) -> Result<ExitStatus> {
    terminal_ui::output_event(SystemEvent::ScriptStarted);
    let mut child = spawn(command(frame_url, product_id, script, host_role), script).await?;
    child.wait().await.context("wait for host script")
}

/// Run a prepared product bundle with output streamed into the terminal UI.
pub async fn run_captured(
    frame_url: &str,
    product_id: &str,
    script: &PreparedScript,
    ui: UiHandle,
    host_role: ScriptHostRole,
) -> Result<ExitStatus> {
    let mut command = command(frame_url, product_id, script, host_role);
    terminal_ui::output_event(SystemEvent::ScriptStarted);
    command.stdout(Stdio::piped()).stderr(Stdio::piped());
    let mut child = spawn(command, script).await?;
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
    script: &PreparedScript,
    host_role: ScriptHostRole,
) -> Command {
    let mut command = Command::new("bun");
    command
        .arg("run")
        .arg("-")
        .current_dir(&script.working_directory)
        .stdin(Stdio::piped())
        .env("TRUAPI_FRAME_URL", frame_url)
        .env("TRUAPI_PRODUCT_ID", product_id)
        .env("TRUAPI_CLI_HOST_ROLE", host_role.as_env_value());
    command
}

async fn spawn(mut command: Command, script: &PreparedScript) -> Result<Child> {
    command.kill_on_drop(true);
    let mut child = command
        .spawn()
        .context("failed to spawn `bun` for the host script (is bun installed?)")?;
    let mut stdin = child.stdin.take().context("open host script stdin")?;
    stdin
        .write_all(&script.bundle)
        .await
        .context("stream product executable bundle to Bun")?;
    stdin
        .shutdown()
        .await
        .context("finish product executable bundle")?;
    Ok(child)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scratch_script_starts_as_a_bun_script_with_dependency_free_example() -> Result<()> {
        let temporary = tempfile::tempdir()?;

        let script = create_scratch_script(temporary.path())?;
        let contents = fs::read_to_string(script)?;

        assert!(contents.starts_with("#!/usr/bin/env bun\n"));
        assert!(!contents.contains("from \"chalk\""));
        assert!(contents.contains("truapi.account.getUserId()"));
        assert_eq!(contents, SCRATCH_TEMPLATE);
        Ok(())
    }

    #[test]
    fn prepared_host_scripts_are_streamed_to_bun_stdin() -> Result<()> {
        let temporary = tempfile::tempdir()?;
        let script = PreparedScript {
            bundle: b"console.log('hello');".to_vec(),
            artifact_identity: "sha256:test".to_string(),
            working_directory: temporary.path().to_path_buf(),
        };
        let command = command(
            "ws://127.0.0.1:1234/capability",
            "example.dot",
            &script,
            ScriptHostRole::SigningHost,
        );
        let command = command.as_std();
        let arguments = command.get_args().collect::<Vec<_>>();

        assert_eq!(command.get_program(), std::ffi::OsStr::new("bun"));
        assert_eq!(arguments[0], std::ffi::OsStr::new("run"));
        assert_eq!(arguments[1], std::ffi::OsStr::new("-"));
        assert_eq!(
            command
                .get_envs()
                .find_map(|(key, value)| { (key == "TRUAPI_CLI_HOST_ROLE").then_some(value) }),
            Some(Some(std::ffi::OsStr::new("signing-host")))
        );
        assert!(command.get_envs().all(|(key, _)| key != "TRUAPI_SCRIPT"));
        Ok(())
    }

    #[tokio::test]
    async fn artifact_identity_changes_with_transitive_module_bytes() -> Result<()> {
        let temporary = tempfile::tempdir()?;
        let dependency = temporary.path().join("dependency.ts");
        let script = temporary.path().join("script.ts");
        fs::write(&dependency, "export const message = 'first';\n")?;
        fs::write(
            &script,
            "import { message } from './dependency.ts'; console.log(message);\n",
        )?;

        let first = prepare(&script).await?;
        let first_again = prepare(&script).await?;
        assert_eq!(first.artifact_identity(), first_again.artifact_identity());
        assert_eq!(first.bundle, first_again.bundle);
        fs::write(&dependency, "export const message = 'second';\n")?;
        let second = prepare(&script).await?;

        assert_ne!(first.artifact_identity(), second.artifact_identity());
        assert_ne!(first.bundle, second.bundle);
        Ok(())
    }
    #[tokio::test]
    async fn executable_bundle_rejects_runtime_resolved_imports() -> Result<()> {
        let temporary = tempfile::tempdir()?;
        let script = temporary.path().join("script.ts");
        fs::write(
            &script,
            "const moduleName = process.argv[2]; await import(moduleName);\n",
        )?;

        let error = match prepare(&script).await {
            Ok(_) => anyhow::bail!("runtime-resolved import was accepted"),
            Err(error) => error,
        };
        assert!(
            error
                .to_string()
                .contains("product bundle retains executable imports")
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
