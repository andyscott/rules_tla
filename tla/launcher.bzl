"""Executable launchers for bundled Java tools."""

_RUNFILES_BASH_INIT = """\
# --- begin runfiles.bash initialization ---
set -euo pipefail
if [[ ! -d "${RUNFILES_DIR:-/dev/null}" && ! -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]]; then
  if [[ -f "$0.runfiles_manifest" ]]; then
    export RUNFILES_MANIFEST_FILE="$0.runfiles_manifest"
  elif [[ -f "$0.runfiles/MANIFEST" ]]; then
    export RUNFILES_MANIFEST_FILE="$0.runfiles/MANIFEST"
  elif [[ -f "$0.runfiles/bazel_tools/tools/bash/runfiles/runfiles.bash" ]]; then
    export RUNFILES_DIR="$0.runfiles"
  fi
fi
if [[ -f "${RUNFILES_DIR:-/dev/null}/bazel_tools/tools/bash/runfiles/runfiles.bash" ]]; then
  source "${RUNFILES_DIR}/bazel_tools/tools/bash/runfiles/runfiles.bash"
elif [[ -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]]; then
  source "$(grep -m1 "^bazel_tools/tools/bash/runfiles/runfiles.bash " \
            "$RUNFILES_MANIFEST_FILE" | cut -d " " -f 2-)"
else
  echo >&2 "ERROR: cannot find @bazel_tools//tools/bash/runfiles:runfiles.bash"
  exit 1
fi
# --- end runfiles.bash initialization ---
"""

def _normalize_runfiles_path(path):
    if path.startswith("/"):
        return path
    if path.startswith("../"):
        return path[3:]
    return "_main/{}".format(path)

def _shell_quote(value):
    return "'{}'".format(value.replace("'", "'\"'\"'"))

def _java_jar_launcher_impl(ctx):
    java_runtime = ctx.toolchains["@bazel_tools//tools/jdk:runtime_toolchain_type"].java_runtime
    executable = ctx.actions.declare_file(ctx.label.name)

    script = """#!/usr/bin/env bash
{runfiles_init}

java_bin=$(rlocation {java_bin})
jar=$(rlocation {jar})

exec "$java_bin" -jar "$jar" "$@"
""".format(
        jar = _shell_quote(_normalize_runfiles_path(ctx.file.jar.short_path)),
        java_bin = _shell_quote(_normalize_runfiles_path(java_runtime.java_executable_runfiles_path)),
        runfiles_init = _RUNFILES_BASH_INIT,
    )

    ctx.actions.write(
        output = executable,
        content = script,
        is_executable = True,
    )

    runfiles = ctx.runfiles(
        transitive_files = depset(transitive = [
            ctx.attr.jar[DefaultInfo].files,
            java_runtime.files,
        ]),
    ).merge(ctx.attr._runfiles[DefaultInfo].default_runfiles)

    return [DefaultInfo(
        executable = executable,
        runfiles = runfiles,
    )]

java_jar_launcher = rule(
    implementation = _java_jar_launcher_impl,
    attrs = {
        "jar": attr.label(
            allow_single_file = [".jar"],
            mandatory = True,
        ),
        "_runfiles": attr.label(
            default = "@bazel_tools//tools/bash/runfiles",
        ),
    },
    executable = True,
    toolchains = [
        "@bazel_tools//tools/jdk:runtime_toolchain_type",
    ],
    doc = "Creates an executable wrapper that launches a Java jar with Bazel's runtime toolchain.",
)
