"""Toolchain definitions for rules_tla."""

def _tla_toolchain_impl(ctx):
    jar_target = ctx.attr.jar[DefaultInfo]

    return [platform_common.ToolchainInfo(
        files = jar_target.files,
        jar = ctx.file.jar,
    )]

tla_toolchain = rule(
    implementation = _tla_toolchain_impl,
    attrs = {
        "jar": attr.label(
            allow_single_file = [".jar"],
            default = "@tla2tools//:tla2tools",
        ),
    },
    doc = "Defines the TLA+ distribution used by rules_tla.",
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
