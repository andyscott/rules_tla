"""Toolchain definitions for rules_tla."""

def _tla_toolchain_impl(ctx):
    worker = ctx.attr.worker[DefaultInfo]

    return [platform_common.ToolchainInfo(
        worker_default_runfiles = worker.default_runfiles,
        worker_executable = ctx.executable.worker,
        worker_files_to_run = worker.files_to_run,
    )]

tla_toolchain = rule(
    implementation = _tla_toolchain_impl,
    attrs = {
        "worker": attr.label(
            cfg = "exec",
            default = "//src/main/java/io/higherkindness/rules_tla:worker",
            executable = True,
        ),
    },
    doc = "Defines the TLA+ worker toolchain used by rules_tla.",
)
