use std::env;
use std::error::Error;
use std::fs;
use std::path::PathBuf;

/// Resolve a Bazel-provided path environment variable into a real filesystem path.
///
/// This handles:
/// - absolute paths
/// - `$(rootpath ...)`-style relative paths under the current working directory
/// - test runfiles under `TEST_SRCDIR` / `TEST_WORKSPACE`
pub fn resolve_bazel_path(var: &str) -> Result<PathBuf, Box<dyn Error>> {
    let raw_value = env::var(var)?;
    let cwd = env::current_dir()?;
    let normalized = if let Some(suffix) = raw_value.strip_prefix("${pwd}/") {
        cwd.join(suffix)
    } else {
        PathBuf::from(&raw_value)
    };
    let raw = normalized;
    let mut attempted = Vec::new();

    if raw.is_absolute() {
        attempted.push(raw.display().to_string());
        if raw.exists() {
            return Ok(raw);
        }
    }

    let cwd_candidate = cwd.join(&raw);
    attempted.push(cwd_candidate.display().to_string());
    if cwd_candidate.exists() {
        return Ok(cwd_candidate);
    }

    if let Ok(test_srcdir) = env::var("TEST_SRCDIR") {
        let srcdir_candidate = PathBuf::from(&test_srcdir).join(&raw);
        attempted.push(srcdir_candidate.display().to_string());
        if srcdir_candidate.exists() {
            return Ok(srcdir_candidate);
        }

        if let Ok(test_workspace) = env::var("TEST_WORKSPACE") {
            let workspace_candidate = PathBuf::from(&test_srcdir).join(test_workspace).join(&raw);
            attempted.push(workspace_candidate.display().to_string());
            if workspace_candidate.exists() {
                return Ok(workspace_candidate);
            }
        }
    }

    Err(format!(
        "could not resolve {var}={raw_value:?}; tried {}",
        attempted.join(", "),
    )
    .into())
}

/// Load an Apalache trace corpus emitted by `apalache_generate_traces`.
///
/// The file is a JSON array of ITF traces. Keeping the transport as a single file
/// makes it stable under Bazel runfiles and stripped output paths.
pub fn load_trace_corpus_from_env(
    var: &str,
) -> Result<Vec<itf::Trace<itf::Value>>, Box<dyn Error>> {
    let path = resolve_bazel_path(var)?;
    let corpus = fs::read_to_string(&path)?;
    let traces = serde_json::from_str(&corpus)?;
    Ok(traces)
}
