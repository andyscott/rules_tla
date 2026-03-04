"""Bzlmod extension entry points for rules_tla."""

load(":repositories.bzl", "protobuf_java_repository", "tla2tools_repository")

_DEFAULT_VERSION = "1.7.4"
_DEFAULT_SHA256 = "936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88"

tla_toolchain = tag_class(attrs = {
    "version": attr.string(default = _DEFAULT_VERSION),
    "sha256": attr.string(default = _DEFAULT_SHA256),
})

def _tla_extension_impl(module_ctx):
    registrations = []

    for mod in module_ctx.modules:
        registrations.extend(mod.tags.toolchain)

    if not registrations:
        registrations = [struct(version = _DEFAULT_VERSION, sha256 = _DEFAULT_SHA256)]

    selected = registrations[-1]

    tla2tools_repository(
        name = "tla2tools",
        sha256 = selected.sha256,
        version = selected.version,
    )

    protobuf_java_repository(name = "protobuf_java")

    return module_ctx.extension_metadata(reproducible = True)

tla = module_extension(
    implementation = _tla_extension_impl,
    tag_classes = {
        "toolchain": tla_toolchain,
    },
    arch_dependent = False,
    os_dependent = False,
)
