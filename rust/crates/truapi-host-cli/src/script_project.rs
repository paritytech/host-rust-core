//! Persistent Product SDK projects created by the script editor.

use std::fs;
use std::path::{Component, Path, PathBuf};
use std::process::Stdio;

use anyhow::{Context, Result, bail};
use serde::Deserialize;
use sha2::{Digest, Sha256};
use tokio::process::Command;

use crate::script_runner;
use crate::terminal_ui::UiHandle;

const SCRIPT: &str = include_str!("../js/sdk-script.ts");
const MANIFEST: &str = include_str!("../js/script-package.json");
const TSCONFIG: &str = include_str!("../js/script-tsconfig.json");
const INSTALL_STAMP: &str = "node_modules/.truapi-host-install";

#[derive(Deserialize)]
struct Manifest {
    #[serde(rename = "truapiHost")]
    host: Option<Metadata>,
}

#[derive(Deserialize)]
struct Metadata {
    script: PathBuf,
}

#[derive(Default, Deserialize)]
#[serde(deny_unknown_fields)]
struct SdkPackages {
    sdk: Option<String>,
    host: Option<String>,
}

/// Create a new project without replacing an existing directory.
pub fn create(root: &Path, destination: Option<&Path>) -> Result<PathBuf> {
    let types = script_runner::script_types()?;
    let mut packages = SdkPackages {
        sdk: std::env::var("TRUAPI_SCRIPT_SDK").ok(),
        host: std::env::var("TRUAPI_SCRIPT_SDK_HOST").ok(),
    };
    if packages.sdk.is_none()
        && packages.host.is_none()
        && let Some(path) = script_runner::script_sdk_config()
    {
        packages = match fs::read(&path) {
            Ok(contents) => serde_json::from_slice(&contents)
                .with_context(|| format!("read local SDK configuration {}", path.display()))?,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => SdkPackages::default(),
            Err(error) => return Err(error).with_context(|| format!("read {}", path.display())),
        };
    }
    create_with_sdk(
        root,
        destination,
        packages.sdk.as_deref(),
        packages.host.as_deref(),
        &types,
    )
}

fn package_spec(spec: &str, project: &Path, name: &str) -> Result<String> {
    let path = Path::new(spec.strip_prefix("file:").unwrap_or(spec));
    if !path.exists() && !path.is_absolute() && !spec.starts_with("file:") {
        return Ok(spec.to_string());
    }
    let contents = fs::read(path).with_context(|| {
        format!(
            "read SDK archive {}; pack the SDK before creating a project",
            path.display()
        )
    })?;
    let digest = hex::encode(Sha256::digest(&contents));
    let relative = format!("vendor/{name}-{digest}.tgz");
    fs::create_dir_all(project.join("vendor"))?;
    fs::write(project.join(&relative), contents)?;
    Ok(format!("file:./{relative}"))
}

fn create_with_sdk(
    root: &Path,
    destination: Option<&Path>,
    sdk: Option<&str>,
    host: Option<&str>,
    types: &[u8],
) -> Result<PathBuf> {
    let destination = destination
        .map(|path| std::env::current_dir().map(|current| current.join(path)))
        .transpose()?;
    let parent = destination
        .as_deref()
        .and_then(Path::parent)
        .unwrap_or(root);
    fs::create_dir_all(parent)
        .with_context(|| format!("create script project parent {}", parent.display()))?;
    let temporary = tempfile::Builder::new()
        .prefix("script-")
        .tempdir_in(parent)?;
    let mut manifest: serde_json::Value = serde_json::from_str(MANIFEST)?;
    if let Some(sdk) = sdk {
        manifest["dependencies"]["@parity/product-sdk"] =
            package_spec(sdk, temporary.path(), "product-sdk")?.into();
    }
    if let Some(host) = host {
        manifest["overrides"]["@parity/product-sdk-host"] =
            package_spec(host, temporary.path(), "product-sdk-host")?.into();
    }
    for (name, contents) in [
        ("script.ts", SCRIPT.as_bytes()),
        ("script.types.d.ts", types),
        ("tsconfig.json", TSCONFIG.as_bytes()),
    ] {
        fs::write(temporary.path().join(name), contents)?;
    }
    fs::write(
        temporary.path().join("package.json"),
        format!("{}\n", serde_json::to_string_pretty(&manifest)?),
    )?;
    let directory = if let Some(destination) = destination {
        fs::create_dir(&destination).with_context(|| {
            format!(
                "create script project {}; choose a new directory",
                destination.display()
            )
        })?;
        if let Err(error) = fs::rename(temporary.path(), &destination) {
            let _ = fs::remove_dir(&destination);
            return Err(error).context("publish script project");
        }
        destination
    } else {
        temporary.keep()
    };
    Ok(directory.join("script.ts"))
}

fn project(script: &Path) -> Result<Option<(PathBuf, Metadata)>> {
    let absolute = std::env::current_dir()?.join(script);
    let parent = absolute
        .parent()
        .context("script has no parent directory")?;
    for directory in parent.ancestors() {
        let path = directory.join("package.json");
        let contents = match fs::read(&path) {
            Ok(contents) => contents,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => continue,
            Err(error) => return Err(error).with_context(|| format!("read {}", path.display())),
        };
        let manifest: Manifest = serde_json::from_slice(&contents)
            .with_context(|| format!("read script project metadata in {}", path.display()))?;
        let Some(metadata) = manifest.host else {
            return Ok(None);
        };
        anyhow::ensure!(
            !metadata.script.as_os_str().is_empty()
                && metadata
                    .script
                    .components()
                    .all(|part| matches!(part, Component::Normal(_))),
            "truapiHost.script in {} must be a path inside the project",
            path.display()
        );
        return Ok(Some((directory.to_path_buf(), metadata)));
    }
    Ok(None)
}

/// Return the managed project root, independent of how its script was selected.
pub fn directory(script: &Path) -> Result<Option<PathBuf>> {
    Ok(project(script)?.map(|(directory, _)| directory))
}

/// Reopen an entrypoint renamed through the project's manifest.
pub fn remembered_script(script: &Path) -> Result<Option<PathBuf>> {
    if script.is_file() {
        return Ok(Some(script.to_path_buf()));
    }
    Ok(project(script)?
        .map(|(directory, metadata)| directory.join(metadata.script))
        .filter(|script| script.is_file()))
}

fn lockfile(directory: &Path) -> Option<PathBuf> {
    ["bun.lock", "bun.lockb"]
        .into_iter()
        .map(|name| directory.join(name))
        .find(|path| path.is_file())
}

fn fingerprint(directory: &Path) -> Result<Option<String>> {
    let Some(lockfile) = lockfile(directory) else {
        return Ok(None);
    };
    let manifest = fs::read(directory.join("package.json"))?;
    let lock = fs::read(lockfile)?;
    let mut digest = Sha256::new();
    digest.update(manifest);
    digest.update(lock);
    Ok(Some(hex::encode(digest.finalize())))
}

fn installed(directory: &Path) -> Result<bool> {
    let Some(fingerprint) = fingerprint(directory)? else {
        return Ok(false);
    };
    let Ok(stamp) = fs::read_to_string(directory.join(INSTALL_STAMP)) else {
        return Ok(false);
    };
    if stamp != fingerprint {
        return Ok(false);
    }
    let manifest: serde_json::Value =
        serde_json::from_slice(&fs::read(directory.join("package.json"))?)?;
    Ok(["dependencies", "devDependencies"]
        .into_iter()
        .all(|field| {
            manifest[field].as_object().is_none_or(|dependencies| {
                dependencies.keys().all(|name| {
                    directory
                        .join("node_modules")
                        .join(name)
                        .join("package.json")
                        .is_file()
                })
            })
        }))
}

/// Install missing managed dependencies while retaining the project's lockfile.
pub async fn prepare(script: &Path, ui: Option<UiHandle>) -> Result<()> {
    let Some(directory) = directory(script)? else {
        return Ok(());
    };
    if installed(&directory)? {
        return Ok(());
    }
    let message = format!("Installing script dependencies in {}", directory.display());
    if let Some(ui) = &ui {
        ui.script_stdout(message);
    } else {
        eprintln!("{message}");
    }
    let mut command = Command::new("bun");
    command
        .arg("install")
        .current_dir(&directory)
        .stdin(Stdio::null())
        .kill_on_drop(true);
    if lockfile(&directory).is_some() {
        command.arg("--frozen-lockfile");
    }
    let status = if let Some(ui) = ui {
        script_runner::capture(command, ui).await
    } else {
        command.status().await.context("run bun install")
    }
    .with_context(|| {
        format!(
            "prepare script project {}; install Bun and retry /script",
            directory.display()
        )
    })?;
    if !status.success() {
        bail!(
            "script dependencies could not be installed in {} (exit {}). Project retained; fix the package or network error and retry /script",
            directory.display(),
            status.code().unwrap_or(1)
        );
    }
    let fingerprint =
        fingerprint(&directory)?.context("bun install succeeded without creating a lockfile")?;
    fs::write(directory.join(INSTALL_STAMP), fingerprint)
        .context("record installed script dependencies")?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn new_projects_carry_the_matching_declarations_without_reading_a_checkout() -> Result<()> {
        let root = tempfile::tempdir()?;
        let script = create_with_sdk(root.path(), None, None, None, b"installed runner types")?;
        assert_eq!(
            fs::read(script.with_extension("types.d.ts"))?,
            b"installed runner types"
        );
        Ok(())
    }

    #[test]
    fn ordinary_projects_keep_the_callers_working_directory() -> Result<()> {
        let root = tempfile::tempdir()?;
        fs::write(
            root.path().join("package.json"),
            r#"{"name":"ordinary-project"}"#,
        )?;
        assert!(directory(&root.path().join("script.ts"))?.is_none());
        Ok(())
    }

    #[test]
    fn creating_a_project_never_overwrites_an_existing_directory() -> Result<()> {
        let root = tempfile::tempdir()?;
        let destination = root.path().join("my project");
        fs::create_dir(&destination)?;
        fs::write(destination.join("script.ts"), "user work")?;

        assert!(create_with_sdk(root.path(), Some(&destination), None, None, b"types").is_err());
        assert_eq!(
            fs::read_to_string(destination.join("script.ts"))?,
            "user work"
        );
        Ok(())
    }

    #[test]
    fn project_manifest_pins_the_sdk_and_can_resolve_a_renamed_entrypoint() -> Result<()> {
        let root = tempfile::tempdir()?;
        let script = create_with_sdk(root.path(), None, Some("0.30.0"), None, b"types")?;
        let directory = script.parent().unwrap();
        let manifest_path = directory.join("package.json");
        let mut manifest: serde_json::Value = serde_json::from_slice(&fs::read(&manifest_path)?)?;
        assert_eq!(manifest["dependencies"]["@parity/product-sdk"], "0.30.0");
        manifest["truapiHost"]["script"] = "renamed.ts".into();
        fs::write(manifest_path, serde_json::to_vec(&manifest)?)?;
        let renamed = directory.join("renamed.ts");
        fs::rename(&script, &renamed)?;

        assert_eq!(remembered_script(&script)?, Some(renamed));
        Ok(())
    }

    #[test]
    fn packed_dependencies_stay_with_the_project_when_the_source_is_removed() -> Result<()> {
        let source = tempfile::tempdir()?;
        let archive = source.path().join("sdk.tgz");
        fs::write(&archive, b"candidate SDK")?;
        let root = tempfile::tempdir()?;
        let host = source.path().join("host.tgz");
        fs::write(&host, b"candidate host")?;
        let script = create_with_sdk(root.path(), None, archive.to_str(), host.to_str(), b"types")?;
        source.close()?;
        let directory = script.parent().unwrap();
        let manifest: serde_json::Value =
            serde_json::from_slice(&fs::read(directory.join("package.json"))?)?;
        for (spec, contents) in [
            (
                &manifest["dependencies"]["@parity/product-sdk"],
                b"candidate SDK".as_slice(),
            ),
            (
                &manifest["overrides"]["@parity/product-sdk-host"],
                b"candidate host".as_slice(),
            ),
        ] {
            let dependency = Path::new(spec.as_str().unwrap().strip_prefix("file:").unwrap());
            assert!(
                dependency.is_relative(),
                "copied projects must keep their SDK"
            );
            assert_eq!(fs::read(directory.join(dependency))?, contents);
        }
        Ok(())
    }

    #[test]
    fn dependency_setup_retries_partial_or_changed_installations() -> Result<()> {
        let root = tempfile::tempdir()?;
        fs::write(
            root.path().join("package.json"),
            r#"{"dependencies":{"example":"1.0.0"}}"#,
        )?;
        fs::write(root.path().join("bun.lock"), "locked")?;
        fs::create_dir_all(root.path().join("node_modules/example"))?;
        fs::write(root.path().join("node_modules/example/package.json"), "{}")?;
        assert!(!installed(root.path())?);
        fs::write(
            root.path().join(INSTALL_STAMP),
            fingerprint(root.path())?.unwrap(),
        )?;
        assert!(installed(root.path())?);
        fs::remove_file(root.path().join("node_modules/example/package.json"))?;
        assert!(!installed(root.path())?);
        fs::write(root.path().join("node_modules/example/package.json"), "{}")?;
        fs::write(root.path().join("bun.lock"), "updated")?;
        assert!(!installed(root.path())?);
        Ok(())
    }
}
