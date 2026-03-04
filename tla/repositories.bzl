"""Repository rules for fetching external TLA+ tools."""

def _tla2tools_repository_impl(repository_ctx):
    repository_ctx.download(
        output = "tla2tools.jar",
        sha256 = repository_ctx.attr.sha256,
        url = "https://github.com/tlaplus/tlaplus/releases/download/v{}/tla2tools.jar".format(repository_ctx.attr.version),
    )

    repository_ctx.file("BUILD.bazel", """\
load("@rules_java//java:defs.bzl", "java_import")

java_import(
    name = "tla2tools",
    jars = ["tla2tools.jar"],
    visibility = ["//visibility:public"],
)
""")

tla2tools_repository = repository_rule(
    implementation = _tla2tools_repository_impl,
    attrs = {
        "sha256": attr.string(mandatory = True),
        "version": attr.string(mandatory = True),
    },
)

def _apalache_repository_impl(repository_ctx):
    repository_ctx.download_and_extract(
        sha256 = repository_ctx.attr.sha256,
        stripPrefix = "apalache-{}".format(repository_ctx.attr.version),
        url = "https://github.com/apalache-mc/apalache/releases/download/v{}/apalache-{}.tgz".format(
            repository_ctx.attr.version,
            repository_ctx.attr.version,
        ),
    )

    repository_ctx.file("BUILD.bazel", """\
filegroup(
    name = "apalache_jar",
    srcs = ["lib/apalache.jar"],
    visibility = ["//visibility:public"],
)
""")

apalache_repository = repository_rule(
    implementation = _apalache_repository_impl,
    attrs = {
        "sha256": attr.string(mandatory = True),
        "version": attr.string(mandatory = True),
    },
)
