"""Repository rules for fetching external TLA+ tools."""

_PROTOBUF_JAVA_VERSION = "4.33.4"
_PROTOBUF_JAVA_SHA256 = "3ca892fd6ea8b37d01bb6917dbc0bf2637548b756753f65a28d4f1d4d982347f"

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

def _protobuf_java_repository_impl(repository_ctx):
    repository_ctx.download(
        output = "protobuf-java.jar",
        sha256 = _PROTOBUF_JAVA_SHA256,
        url = "https://repo1.maven.org/maven2/com/google/protobuf/protobuf-java/{0}/protobuf-java-{0}.jar".format(_PROTOBUF_JAVA_VERSION),
    )

    repository_ctx.file("BUILD.bazel", """\
load("@rules_java//java:defs.bzl", "java_import")

java_import(
    name = "protobuf_java",
    jars = ["protobuf-java.jar"],
    visibility = ["//visibility:public"],
)
""")

protobuf_java_repository = repository_rule(
    implementation = _protobuf_java_repository_impl,
)
