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

def _apalache_toolchain_impl(ctx):
    jar_target = ctx.attr.jar[DefaultInfo]

    return [platform_common.ToolchainInfo(
        jar = ctx.file.jar,
        files = jar_target.files,
    )]

apalache_toolchain = rule(
    implementation = _apalache_toolchain_impl,
    attrs = {
        "jar": attr.label(
            allow_single_file = [".jar"],
            default = "@apalache//:apalache_jar",
        ),
    },
    doc = "Defines the Apalache distribution used by rules_tla.",
)
